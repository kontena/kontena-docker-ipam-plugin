require 'ipaddr'

module Addresses
  class Request < Mutations::Command
    class AddressError < RuntimeError
      attr_reader :sym
      def initialize(sym)
        @sym = sym
      end
    end

    include Logging

    required do
      model :policy
      string :pool_id
    end

    optional do
      ipaddr :address, discard_empty: true
    end

    def validate
      unless @pool = AddressPool.get(pool_id)
        add_error(:pool, :not_found, "Pool not found: #{pool_id}")
      end

      if self.address && @pool
        unless @pool.subnet.include?(self.address)
          add_error(:address, :out_of_pool, "Address #{self.address} outside of pool subnet #{@pool.subnet}")
        end
      end
    end

    def execute
      if self.address
        info "request static address #{self.address} in pool #{@pool.id} with subnet #{@pool.subnet}"

        request_static
      else
        info "request dynamic address in pool #{@pool.id} with subnet #{@pool.subnet}"

        request_dynamic
      end
    rescue AddressError => error
      add_error(:address, error.sym, error.message)
    end

    # Allocate static self.address within @pool.
    #
    # @raise AddressError if reservation failed (conflict)
    # @return [Address] reserved address
    def request_static
      # reserve
      return @pool.create_address(self.address)

    rescue Address::Conflict => error
      raise AddressError.new(:conflict), "Allocation conflict for address #{self.address}: #{error.message}"
    end

    # Allocate dynamic address within @pool.
    # Retries allocation on AddressConflict
    #
    # @raise AddressError if allocation failed (pool is full)
    # @return [Address] reserved address
    def request_dynamic
      available = @pool.available_addresses

      info "pool #{@pool} allocates from #{@pool.allocation_range} and has #{available.length} available addresses"

      # allocate
      unless allocate_address = policy.allocate_address(available)
        raise AddressError.new(:allocate), "No addresses available for allocation"
      end

      # reserve
      return @pool.create_address(allocate_address)

    rescue Address::Conflict => error
      warn "retry dynamic address allocation: #{error.message}"

      # should make progress given that we refresh the set of reserved addresses, and raise a different error if the pool is full
      retry
    end
  end
end
