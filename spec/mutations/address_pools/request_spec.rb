describe AddressPools::Request do
  let :policy do
    Policy.new(
      'KONTENA_IPAM_SUPERNET' => '10.80.0.0/12',
      'KONTENA_IPAM_SUBNET_LENGTH' => '24',
    )
  end

  let :etcd do
    spy()
  end

  before do
    EtcdModel.etcd = $etcd = etcd
  end

  describe '#validate' do
    it 'rejects a missing network' do
      subject = described_class.new(policy: policy)

      expect(subject).to have_errors
    end

    it 'accepts a network' do
      subject = described_class.new(policy: policy, network: 'kontena')

      expect(subject).not_to have_errors, subject.validation_outcome.errors.inspect
    end

    it 'rejects an invalid subnet' do
      subject = described_class.new(policy: policy, network: 'kontena', subnet: 'asdf')

      expect(subject).to have_errors
      expect(subject.validation_outcome.errors.symbolic[:subnet]).to eq :invalid
    end

    it 'accepts a valid subnet' do
      subject = described_class.new(policy: policy, network: 'kontena', subnet: '10.81.0.0/16')

      expect(subject).not_to have_errors, subject.validation_outcome.errors.inspect
    end

    it 'rejects an invalid iprange' do
      subject = described_class.new(policy: policy, network: 'kontena', subnet: '10.81.0.0/16', iprange: 'asdf')

      expect(subject).to have_errors
      expect(subject.validation_outcome.errors.symbolic[:iprange]).to eq :invalid
    end

    it 'accepts a valid iprange' do
      subject = described_class.new(policy: policy, network: 'kontena', subnet: '10.81.0.0/16', iprange: '10.81.128.0/17')

      expect(subject).not_to have_errors, subject.validation_outcome.errors.inspect
    end

    it 'rejects ipv6 pool request' do
      subject = described_class.new(policy: policy, network: 'kontena', subnet: '10.81.0.0/16', iprange: '10.81.128.0/17', ipv6: true)
      expect(subject).to have_errors
      expect(subject.validation_outcome.errors.symbolic[:ipv6]).to eq :not_supported
    end

    it 'default to false ipv6 when ipv6 flag nil' do
      subject = described_class.new(policy: policy, network: 'kontena', subnet: '10.81.0.0/16', iprange: '10.81.128.0/17', ipv6: nil)
      expect(subject).not_to have_errors
    end
  end

  describe '#reserved_subnets' do
    let :subject do
      described_class.new(policy: policy, network: 'kontena')
    end

    it 'returns subnets if they exists in etcd' do
      expect(AddressPool).to receive(:list).and_return([
          AddressPool.new("kontena", subnet: IPAddr.new("10.81.0.0/16")),
      ])

      expect(subject.reserved_subnets).to eq [
        IPAddr.new("10.81.0.0/16"),
      ]
    end
  end

  describe '#execute' do
    context 'allocating a dynamic pool' do
      let :subject do
        described_class.new(policy: policy, network: 'kontena')
      end

      it 'returns address pool if it already exists in etcd' do
        expect(AddressPool).to receive(:get).with('kontena').and_return(AddressPool.new('kontena', subnet: IPAddr.new('10.81.0.0/16')))

        outcome = subject.run

        expect(outcome).to be_success
        expect(outcome.result).to eq AddressPool.new('kontena', subnet: IPAddr.new('10.81.0.0/16'))
      end

      it 'returns new address pool' do
        expect(AddressPool).to receive(:get).with('kontena').and_return(nil)
        expect(AddressPool).to receive(:list).with(no_args).and_return([])
        expect(policy).to receive(:allocate_subnets).and_yield(IPAddr.new('10.80.0.0/24'))
        expect(AddressPool).to receive(:create).with('kontena', subnet: IPAddr.new('10.80.0.0/24'), iprange: nil).and_return(AddressPool.new('kontena', subnet: IPAddr.new('10.80.0.0/24')))
        expect(etcd).to receive(:set).with('/kontena/ipam/addresses/kontena/', dir: true)

        outcome = subject.run

        expect(outcome).to be_success, outcome.errors.inspect
        expect(outcome.result).to eq AddressPool.new('kontena', subnet: IPAddr.new('10.80.0.0/24'))
      end

      it 'returns a different address pool if some other network already exists in etcd' do
        expect(AddressPool).to receive(:get).with('kontena').and_return(nil)
        expect(AddressPool).to receive(:list).with(no_args).and_return([
          AddressPool.new('test', subnet: IPAddr.new('10.80.0.0/24')),
        ])
        expect(policy).to receive(:allocate_subnets).with([IPAddr.new('10.80.0.0/24')]).and_yield(IPAddr.new('10.80.1.0/24'))
        expect(AddressPool).to receive(:create).with('kontena', subnet: IPAddr.new('10.80.1.0/24'), iprange: nil).and_return(AddressPool.new('kontena', subnet: IPAddr.new('10.80.1.0/24')))

        expect(etcd).to receive(:set).with('/kontena/ipam/addresses/kontena/', dir: true)

        outcome = subject.run

        expect(outcome).to be_success
        expect(outcome.result).to eq AddressPool.new('kontena', subnet: IPAddr.new('10.80.1.0/24'))
      end

      it 'fails if the supernet is exhausted' do
        pools = []
        subnets = []
        (80..95).each do |i|
          subnets << subnet = IPAddr.new("10.#{i}.0.0/16")
          pools << AddressPool.new("test-#{i}", subnet: subnet)
        end
        expect(AddressPool).to receive(:get).with('kontena').and_return(nil)
        expect(AddressPool).to receive(:list).with(no_args).and_return(pools)
        expect(policy).to receive(:allocate_subnets).with(subnets).and_return(nil)

        outcome = subject.run

        expect(outcome).to_not be_success
        expect(outcome.errors.symbolic[:subnet]).to eq :allocate
      end
    end

    context 'allocating a static pool' do
      let :subject do
        described_class.new(policy: policy, network: 'kontena', subnet: '10.81.0.0/16')
      end

      it 'returns address pool if it already exists in etcd' do
        expect(AddressPool).to receive(:get).with('kontena').and_return(AddressPool.new('kontena', subnet: IPAddr.new('10.81.0.0/16')))

        outcome = subject.run

        expect(outcome).to be_success
        expect(outcome.result).to eq AddressPool.new('kontena', subnet: IPAddr.new('10.81.0.0/16'))
      end

      it 'fails if the network already exists with a different subnet' do
        expect(AddressPool).to receive(:get).with('kontena').and_return(AddressPool.new('kontena', subnet: IPAddr.new('10.80.0.0/16')))

        outcome = subject.run

        expect(outcome).to_not be_success
        expect(outcome.errors.symbolic[:subnet]).to eq :config
      end

      it 'fails if a network already exists with the same subnet' do
        expect(AddressPool).to receive(:get).with('kontena').and_return(nil)
        expect(AddressPool).to receive(:list).with(no_args).and_return([
          AddressPool.new('test', subnet: IPAddr.new('10.81.0.0/16')),
        ])

        outcome = subject.run

        expect(outcome).to_not be_success
        expect(outcome.errors.symbolic[:subnet]).to eq :conflict
      end

      it 'fails if a network already exists with an overlapping subnet' do
        expect(AddressPool).to receive(:get).with('kontena').and_return(nil)
        expect(AddressPool).to receive(:list).with(no_args).and_return([
          AddressPool.new('test', subnet: IPAddr.new('10.81.10.0/24')),
        ])

        outcome = subject.run

        expect(outcome).to_not be_success
        expect(outcome.errors.symbolic[:subnet]).to eq :conflict
      end

      it 'returns address pool if some other network exists in etcd' do
        expect(AddressPool).to receive(:get).with('kontena').and_return(nil)
        expect(AddressPool).to receive(:list).with(no_args).and_return([
          AddressPool.new('test', subnet: IPAddr.new('10.80.0.0/24')),
        ])
        expect(AddressPool).to receive(:create).with('kontena', subnet: IPAddr.new('10.81.0.0/16'), iprange: nil).and_return(AddressPool.new('kontena', subnet: IPAddr.new('10.81.0.0/16')))
        expect(etcd).to receive(:set).with('/kontena/ipam/addresses/kontena/', dir: true)

        outcome = subject.run

        expect(outcome).to be_success
        expect(outcome.result).to eq AddressPool.new('kontena', subnet: IPAddr.new('10.81.0.0/16'))
      end
    end

    context 'allocating a static pool with an iprange' do
      let :subject do
        described_class.new(policy: policy, network: 'kontena', subnet: '10.81.0.0/16', iprange: '10.81.128.0/17')
      end

      it 'fails if the network already exists with a different iprange' do
        expect(AddressPool).to receive(:get).with('kontena').and_return(AddressPool.new('kontena', subnet: IPAddr.new('10.81.0.0/16'), iprange: IPAddr.new('10.80.0.0/17')))

        outcome = subject.run

        expect(outcome).to_not be_success
        expect(outcome.errors.symbolic[:iprange]).to eq :config
      end
    end
  end
end
