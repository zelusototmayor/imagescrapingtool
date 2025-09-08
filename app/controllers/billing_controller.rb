class BillingController < ApplicationController
  def checkout
    render json: { disabled: true, message: 'Billing not yet implemented' }
  end
end