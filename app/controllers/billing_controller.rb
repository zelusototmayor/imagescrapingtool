class BillingController < ApplicationController
  before_action :authenticate_user!, except: [:webhook]
  protect_from_forgery except: [:webhook]

  def checkout
    begin
      # Create or retrieve Stripe customer
      customer = find_or_create_stripe_customer

      # Create checkout session
      session = Stripe::Checkout::Session.create({
        customer: customer.id,
        payment_method_types: ['card'],
        line_items: [{
          price: ENV['STRIPE_PRICE_ID'], # €5/month subscription price ID
          quantity: 1,
        }],
        mode: 'subscription',
        success_url: "#{request.base_url}/dashboard?session_id={CHECKOUT_SESSION_ID}",
        cancel_url: "#{request.base_url}/dashboard",
        metadata: {
          user_id: current_user.id
        }
      })

      render json: { checkout_url: session.url }
    rescue Stripe::StripeError => e
      render json: { error: e.message }, status: :unprocessable_content
    end
  end

  def webhook
    payload = request.body.read
    sig_header = request.env['HTTP_STRIPE_SIGNATURE']
    endpoint_secret = ENV['STRIPE_WEBHOOK_SECRET']

    begin
      event = Stripe::Webhook.construct_event(payload, sig_header, endpoint_secret)
    rescue JSON::ParserError => e
      render json: { error: 'Invalid payload' }, status: :bad_request
      return
    rescue Stripe::SignatureVerificationError => e
      render json: { error: 'Invalid signature' }, status: :bad_request
      return
    end

    handle_stripe_event(event)
    render json: { received: true }
  end

  private

  def find_or_create_stripe_customer
    if current_user.stripe_customer_id.present?
      Stripe::Customer.retrieve(current_user.stripe_customer_id)
    else
      customer = Stripe::Customer.create({
        email: current_user.email,
        metadata: {
          user_id: current_user.id
        }
      })
      current_user.update!(stripe_customer_id: customer.id)
      customer
    end
  end

  def handle_stripe_event(event)
    case event['type']
    when 'checkout.session.completed'
      session = event['data']['object']
      handle_successful_payment(session)
    when 'customer.subscription.updated'
      subscription = event['data']['object']
      handle_subscription_update(subscription)
    when 'customer.subscription.deleted'
      subscription = event['data']['object']
      handle_subscription_cancellation(subscription)
    end
  end

  def handle_successful_payment(session)
    user = User.find(session['metadata']['user_id'])
    subscription = Stripe::Subscription.retrieve(session['subscription'])

    user.update!(
      subscription_status: :premium,
      stripe_subscription_id: subscription.id
    )
  end

  def handle_subscription_update(subscription)
    user = User.find_by(stripe_subscription_id: subscription.id)
    return unless user

    if subscription.status == 'active'
      user.update!(subscription_status: :premium)
    else
      user.update!(subscription_status: :free)
    end
  end

  def handle_subscription_cancellation(subscription)
    user = User.find_by(stripe_subscription_id: subscription.id)
    return unless user

    user.update!(
      subscription_status: :free,
      stripe_subscription_id: nil
    )
  end
end