import Stripe from "npm:stripe@17.4.0";
import { createClient } from "npm:@supabase/supabase-js@2";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, {
  apiVersion: "2024-06-20",
});
const webhookSecret = Deno.env.get("STRIPE_WEBHOOK_SECRET")!;

// service_role: this function is the one legitimate writer of subscription state.
const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

Deno.serve(async (req) => {
  const signature = req.headers.get("Stripe-Signature");
  const body = await req.text();

  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(body, signature!, webhookSecret);
  } catch (err) {
    console.error("Webhook signature verification failed", err);
    return new Response("Invalid signature", { status: 400 });
  }

  switch (event.type) {
    case "checkout.session.completed": {
      const session = event.data.object as Stripe.Checkout.Session;
      const userId = session.client_reference_id;
      const customerId = typeof session.customer === "string" ? session.customer : session.customer?.id;
      const subscriptionId = typeof session.subscription === "string" ? session.subscription : session.subscription?.id;

      if (userId) {
        const { error } = await admin.from("subscriptions").upsert({
          user_id: userId,
          status: "active",
          stripe_customer_id: customerId,
          stripe_subscription_id: subscriptionId,
          updated_at: new Date().toISOString(),
        }, { onConflict: "user_id" });
        if (error) console.error("Could not upsert subscription on checkout completion", error);
      }
      break;
    }

    case "customer.subscription.updated":
    case "customer.subscription.deleted": {
      const sub = event.data.object as Stripe.Subscription;
      const customerId = typeof sub.customer === "string" ? sub.customer : sub.customer.id;
      const status = event.type === "customer.subscription.deleted" ? "canceled" : sub.status;

      // Newer Stripe API versions moved current_period_end off the top-level
      // Subscription object onto each subscription item instead.
      const periodEndUnix = sub.current_period_end ?? sub.items?.data?.[0]?.current_period_end;

      const { error } = await admin
        .from("subscriptions")
        .update({
          status,
          current_period_end: periodEndUnix ? new Date(periodEndUnix * 1000).toISOString() : null,
          updated_at: new Date().toISOString(),
        })
        .eq("stripe_customer_id", customerId);
      if (error) console.error("Could not update subscription status", error);
      break;
    }

    case "invoice.payment_failed": {
      const invoice = event.data.object as Stripe.Invoice;
      const customerId = typeof invoice.customer === "string" ? invoice.customer : invoice.customer?.id;

      if (customerId) {
        const { error } = await admin
          .from("subscriptions")
          .update({ status: "past_due", updated_at: new Date().toISOString() })
          .eq("stripe_customer_id", customerId);
        if (error) console.error("Could not mark subscription past_due", error);
      }
      break;
    }

    default:
      break;
  }

  return new Response(JSON.stringify({ received: true }), {
    headers: { "Content-Type": "application/json" },
  });
});
