require 'ipaddr'

module AddressPools
  class Release < Mutations::Command
    include Logging

    required do
      string :pool_id
    end

    def validate
      unless @pool = AddressPool.get(pool_id)
        add_error(:pool_id, :notfound, "AddressPool not found: #{pool_id}")
      end
    end

    def execute
      @pool.release!

      if @pool.cleanup
        info "Release pool=#{@pool.id}: cleanup deleted"
      else
        info "Release pool=#{@pool.id}: cleanup skipped"
      end
    end
  end
end
