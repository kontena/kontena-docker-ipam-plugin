require 'optparse'

module Commands
  class Cleanup
    include Logging

    attr_accessor :docker_networks
    attr_accessor :pool
    attr_accessor :addresses

    def self.parse!
      command = new

      OptionParser.new do |opts|
        opts.banner = "Usage: kontena-ipam-cleanup [--docker-networks] [--pool POOL IPADDR...]"
        opts.on("--docker-networks", "Cleanup Docker networks") do |flag|
          command.docker_networks = flag
        end
        opts.on("--pool=POOL", "Cleanup given pool using adddresses given") do |pool|
          command.pool = pool
        end
      end.parse!

      command.addresses = ARGV
      command
    end

    def execute
      if self.docker_networks
        info "Cleanup Docker networks..."

        docker_client = DockerClient.new
        docker_client.ipam_networks_addresses do |network, pool, addresses|
          info "Cleanup Docker network #{network} using Kontena IPAM pool #{pool} with #{addresses.length} local Docker container endpoints"

          Addresses::Cleanup.run!(
            pool_id: pool,
            addresses: addresses,
          )
        end
      end

      if self.pool
        info "Cleanup Kontena IPAM pool #{self.pool} with #{self.addresses.length} active addresses"

        Addresses::Cleanup.run!(
          pool_id: self.pool,
          addresses: self.addresses,
        )
      end
    end
  end
end
