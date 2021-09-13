class DynamicPercentageDiscount
  def initialize(message)
    @message = message
    @total_new_price = Decimal.new(0)
  end

  def apply(line_item, amount, bundle_price, length, index)
    @amount = amount
    @discount = (Decimal.new(100) - @amount) / 100
    if index < (length - 1)
      line_item.change_line_price(line_item.line_price * @discount, message: @message)
    elsif index = (length - 1)
      line_item.change_line_price(bundle_price - Money.new(cents: @total_new_price), message: @message)
    end
    @updated_line_price = line_item.line_price.cents.round(2)
    @total_new_price =  @total_new_price + @updated_line_price
  end
end
