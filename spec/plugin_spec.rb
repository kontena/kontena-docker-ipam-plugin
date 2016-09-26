require 'rack/test'

describe IpamPlugin do
  include Rack::Test::Methods

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
    $etcd = EtcdModel.etcd = etcd
  end

  let :app do
    described_class.new
  end

  before do
    described_class.policy = policy
  end

  def api_post(url, params = {})
    if params.nil?
      post url
    else
      post url, params.to_json, { 'CONTENT_TYPE' => 'application/json' }
    end

    if last_response.content_type == 'application/json'
      JSON.parse(last_response.body)
    else
      last_response.body
    end
  end

  describe '/Plugin.Activate' do
    it 'implements IpamDriver' do
      data = api_post '/Plugin.Activate', nil

      expect(data).to eq({ 'Implements' => ['IpamDriver'] })
    end
  end

  describe '/IpamDriver.GetCapabilities' do
    it 'does not require request replay' do
      data = api_post '/IpamDriver.GetCapabilities', nil

      expect(last_response).to be_ok
      expect(data['RequiresMACAddress']).to be_falsey
    end
  end

  describe '/IpamDriver.RequestPool' do
    it 'returns 400 on invalid JSON' do
      data = api_post '/Plugin.Activate', 'invalid'

      expect(last_response.status).to eq(400), last_response.errors

      expect(data).to match(/^JSON parse error: \d*: unexpected token at '\"invalid\"'$/)
    end

    it 'returns 400 on missing network option' do
      data = api_post '/IpamDriver.RequestPool', {}

      expect(last_response.status).to eq(400), last_response.errors

      expect(data).to eq('Error' => "Network can't be nil")
    end

    it 'returns 400 on invalid pool' do
      data = api_post '/IpamDriver.RequestPool', { 'Options' => { 'network' => 'test'}, 'Pool' => 'xxx' }

      expect(last_response.status).to eq(400), last_response.errors

      expect(data).to eq('Error' => "Invalid address")
    end

    it 'accepts with only the required parameters' do
      expect(AddressPools::Request).to receive(:run!).with(policy: policy, network: 'test', subnet: nil, iprange: nil, ipv6: nil).and_return(AddressPool.new('test', subnet: IPAddr.new('10.80.0.0/24')))

      data = api_post '/IpamDriver.RequestPool', { 'Options' => { 'network' => 'test'}}

      expect(last_response).to be_ok, last_response.errors
      expect(data).to eq('PoolID' => 'test', 'Pool' => '10.80.0.0/24', 'Data' => {})
    end

    it 'accepts with an empty optional param' do
      expect(AddressPools::Request).to receive(:run!).with(policy: policy, network: 'test', subnet: '', iprange: '', ipv6: nil).and_return(AddressPool.new('test', subnet: IPAddr.new('10.80.0.0/24')))

      data = api_post '/IpamDriver.RequestPool', { 'Options' => { 'network' => 'test'}, 'Pool' => '', 'SubPool' => ''}

      expect(last_response).to be_ok, last_response.errors
      expect(data).to eq('PoolID' => 'test', 'Pool' => '10.80.0.0/24', 'Data' => {})
    end

    it 'accepts with an optional pool' do
      expect(AddressPools::Request).to receive(:run!).with(policy: policy, network: 'kontena', subnet: '10.81.0.0/16', iprange: nil, ipv6: nil).and_return(AddressPool.new('kontena', subnet: IPAddr.new('10.80.0.0/16')))

      data = api_post '/IpamDriver.RequestPool', { 'Options' => { 'network' => 'kontena'}, 'Pool' => '10.81.0.0/16'}

      expect(last_response).to be_ok, last_response.errors
      expect(data).to eq('PoolID' => 'kontena', 'Pool' => '10.80.0.0/16', 'Data' => {})
    end

    it 'accepts with an optional iprange' do
      expect(AddressPools::Request).to receive(:run!).with(policy: policy, network: 'kontena', subnet: '10.81.0.0/16', iprange: '10.81.127.0/17', ipv6: nil).and_return(AddressPool.new('kontena', subnet: IPAddr.new('10.80.0.0/16')))

      data = api_post '/IpamDriver.RequestPool', { 'Options' => { 'network' => 'kontena'}, 'Pool' => '10.81.0.0/16', 'SubPool' => '10.81.127.0/17'}

      expect(last_response).to be_ok, last_response.errors
      expect(data).to eq('PoolID' => 'kontena', 'Pool' => '10.80.0.0/16', 'Data' => {})
    end
  end

  describe '/IpamDriver.RequestAddress' do
    let :pool do
      AddressPool.new('test', subnet: IPAddr.new('10.80.0.0/24'))
    end

    let :addr1 do
      Address.new('test', '10.80.0.1', address: pool.subnet.subnet_addr('10.80.0.1'))
    end
    let :addr63 do
      Address.new('test', '10.80.0.63', address: pool.subnet.subnet_addr('10.80.0.63'))
    end

    it 'accepts with only the required parameters' do
      expect(Addresses::Request).to receive(:run!).with(policy: policy, pool_id: 'test', address: nil).and_return(addr63)
      data = api_post '/IpamDriver.RequestAddress', { 'PoolID' => 'test'}

      expect(last_response).to be_ok, last_response.errors
      expect(data).to eq('Address' => '10.80.0.63/24', 'Data' => {})
    end

    it 'accepts with an empty optional params' do
      expect(Addresses::Request).to receive(:run!).with(policy: policy, pool_id: 'test', address: '').and_return(addr63)

      data = api_post '/IpamDriver.RequestAddress', { 'PoolID' => 'test', 'Address' => ''}

      expect(last_response).to be_ok, last_response.errors
      expect(data).to eq('Address' => '10.80.0.63/24', 'Data' => {})
    end

    it 'accepts with an optional params' do
      expect(Addresses::Request).to receive(:run!).with(policy: policy, pool_id: 'test', address: '10.80.0.1').and_return(addr1)

      data = api_post '/IpamDriver.RequestAddress', { 'PoolID' => 'test', 'Address' => '10.80.0.1'}

      expect(last_response).to be_ok, last_response.errors
      expect(data).to eq('Address' => '10.80.0.1/24', 'Data' => {})
    end
  end

  describe '/IpamDriver.ReleaseAddress' do
    it 'accepts the required parameters' do
      # XXX: with netmask or not?
      expect(Addresses::Release).to receive(:run!).with(pool_id: 'test', address: '10.80.0.63/24').and_return(nil)

      data = api_post '/IpamDriver.ReleaseAddress', { 'PoolID' => 'test', 'Address' => '10.80.0.63/24'}

      expect(last_response).to be_ok, last_response.errors
      expect(data).to eq({})
    end
  end

  describe '/IpamDriver.ReleasePool' do
    it 'accepts the required parameters' do
      expect(AddressPools::Release).to receive(:run!).with(pool_id: 'test').and_return(nil)

      data = api_post '/IpamDriver.ReleasePool', { 'PoolID' => 'test' }

      expect(last_response).to be_ok, last_response.errors
      expect(data).to eq({})
    end
  end
end
