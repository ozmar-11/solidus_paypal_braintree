module SolidusPaypalBraintree
  class Source < ApplicationRecord
    PAYPAL = "PayPalAccount"
    APPLE_PAY = "ApplePayCard"
    CREDIT_CARD = "CreditCard"

    belongs_to :user, class_name: Spree::UserClassHandle.new
    belongs_to :payment_method, class_name: 'Spree::PaymentMethod'
    has_many :payments, as: :source, class_name: "Spree::Payment"

    belongs_to :customer, class_name: "SolidusPaypalBraintree::Customer"

    validates :payment_type, inclusion: [PAYPAL, APPLE_PAY, CREDIT_CARD]

    scope(:with_payment_profile, -> { joins(:customer) })
    scope(:credit_card, -> { where(payment_type: CREDIT_CARD) })

    delegate :last_4, :card_type, to: :braintree_payment_method, allow_nil: true
    alias_method :last_digits, :last_4

    # we are not currenctly supporting an "imported" flag
    def imported
      false
    end

    def actions
      %w[capture void credit]
    end

    def can_capture?(payment)
      payment.pending? || payment.checkout?
    end

    def can_void?(payment)
      return false unless payment.response_code
      transaction = braintree_client.transaction.find(payment.response_code)
      Gateway::VOIDABLE_STATUSES.include?(transaction.status)
    rescue Braintree::NotFoundError
      false
    end

    def can_credit?(payment)
      payment.completed? && payment.credit_allowed > 0
    end

    def friendly_payment_type
      I18n.t(payment_type.underscore, scope: "solidus_paypal_braintree.payment_type")
    end

    def apple_pay?
      payment_type == APPLE_PAY
    end

    def paypal?
      payment_type == PAYPAL
    end

    def credit_card?
      payment_type == CREDIT_CARD
    end

    def display_number
      "XXXX-XXXX-XXXX-#{last_digits.to_s.rjust(4, 'X')}"
    end

    private

    def braintree_payment_method
      return unless braintree_client && credit_card?
      @braintree_payment_method ||= braintree_client.payment_method.find(token)
    rescue Braintree::NotFoundError, ArgumentError => e
      Rails.logger.warn("#{e}: token unknown or missing for #{inspect}")
      nil
    end

    def braintree_client
      @braintree_client ||= payment_method.try(:braintree)
    end
  end
end
