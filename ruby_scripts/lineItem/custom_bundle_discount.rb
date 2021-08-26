class CustomBundleDiscount < Campaign
  def initialize(condition, customer_qualifier, cart_qualifier, discount, full_bundles_only, bundle_price, bundle_products)
    super(condition, customer_qualifier, cart_qualifier, nil)
    @bundle_products = bundle_products
    @discount = discount
    @full_bundles_only = full_bundles_only
    @bundle_price = Money.new(cents: bundle_price * 100)
    @split_items = []
    @bundle_items = []
  end

  def check_bundles(cart)
      sorted_items = cart.line_items.sort_by{|line_item| line_item.variant.price}.reverse
      bundled_items = @bundle_products.map do |bitem|
        quantity_required = bitem[:quantity].to_i
        qualifiers = bitem[:qualifiers]
        type = bitem[:type].to_sym
        case type
          when :ptype
            items = sorted_items.select { |item| qualifiers.include?(item.variant.product.product_type) && !item.discounted? }
          when :ptag
            items = sorted_items.select { |item| (qualifiers & item.variant.product.tags).length > 0 && !item.discounted? }
          when :pid
            qualifiers.map!(&:to_i)
            items = sorted_items.select { |item| qualifiers.include?(item.variant.product.id) && !item.discounted? }
          when :vid
            qualifiers.map!(&:to_i)
            items = sorted_items.select { |item| qualifiers.include?(item.variant.id) && !item.discounted? }
          when :vsku
            items = sorted_items.select { |item| (qualifiers & item.variant.skus).length > 0 && !item.discounted? }
        end

        total_quantity = items.reduce(0) { |total, item| total + item.quantity }
        {
          has_all: total_quantity >= quantity_required,
          total_quantity: total_quantity,
          quantity_required: quantity_required,
          total_possible: (total_quantity / quantity_required).to_i,
          items: items
        }
      end

      max_bundle_count = bundled_items.map{ |bundle| bundle[:total_possible] }.min if @full_bundles_only
      if bundled_items.all? { |item| item[:has_all] }
        if @full_bundles_only
          bundled_items.each do |bundle|
            bundle_quantity = bundle[:quantity_required] * max_bundle_count
            split_out_extra_quantity(cart, bundle[:items], bundle[:total_quantity], bundle_quantity)
          end
        else
          bundled_items.each do |bundle|
            bundle[:items].each do |item|
              @bundle_items << item
              cart.line_items.delete(item)
            end
          end
        end
        return true
      end
      false
  end

  def split_out_extra_quantity(cart, items, total_quantity, quantity_required)
    items_to_split = quantity_required
    items.each do |item|
      break if items_to_split == 0
      if item.quantity > items_to_split
        @bundle_items << item.split({take: items_to_split})
        @split_items << item
        items_to_split = 0
      else
        @bundle_items << item
        split_quantity = item.quantity
        items_to_split -= split_quantity
      end
      cart.line_items.delete(item)
    end
    cart.line_items.concat(@split_items)
    @split_items.clear
  end

  def calc_discount
    total_cost = Money.zero
    total_quantity = 0
    @bundle_items.each do |item|
      total_cost += item.line_price
      total_quantity += item.quantity
    end

    bundle_products_count = 0
    @bundle_products.each do |bitem|
      bundle_products_count += bitem[:quantity].to_i
    end

    bundle_count = total_quantity / bundle_products_count

    @amount = total_cost - @bundle_price * bundle_count
  end

  def run(cart)
    raise "Campaign requires a discount" unless @discount
    return unless qualifies?(cart)

    if check_bundles(cart)
      calc_discount()
      @bundle_items.each { |item| @discount.apply(item, @amount) }
    end
    @bundle_items.reverse.each { |item| cart.line_items.prepend(item) }
  end
end
