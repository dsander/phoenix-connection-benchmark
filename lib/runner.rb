require 'open3'
require 'erb'

class Runner
  attr_reader :token, :workers, :kvip

  def initialize
    @token = ENV['DO_TOKEN'] || Config.digital_ocean_token
    @workers = Config.workers
  end

  def create_consul
    @kvip = run("echo $(docker-machine ip bench-kv-store)", streaming_output: false, allow_failure: true).strip
    return if @kvip =~ /(?:[0-9]{1,3}\.){3}[0-9]{1,3}/

    puts "Creating consul container ..."
    run("docker-machine create \
                        --driver=digitalocean \
                        --digitalocean-access-token=#{token} \
                        --digitalocean-size=#{Config.kv_store.size} \
                        --digitalocean-region=#{Config.kv_store.region} \
                        --digitalocean-image=#{Config.kv_store.image} \
                        --digitalocean-private-networking=true \
                          bench-kv-store")
    run("docker $(docker-machine config bench-kv-store) run -d \
                --net=host progrium/consul --server -bootstrap-expect 1")

    @kvip = run("echo $(docker-machine ip bench-kv-store)", streaming_output: false).strip
  end

  def create_cluster
    threads = []

    threads << Thread.new do
      create_swarm(master: true)
    end

    (1..workers).each do |i|
      threads << Thread.new do
        create_swarm(master: false, number: i)
      end
      sleep 1
    end
    threads.each(&:join)
  end

  def create_swarm(options)
    name = if options[:master]
      "bench-master"
    else
      "bench-agent-#{options[:number]}"
    end
    puts "Creating swarm container #{name} ..."

    run("docker-machine create \
                        --driver=digitalocean \
                        --digitalocean-access-token=#{token} \
                        --digitalocean-size=#{Config.worker.size} \
                        --digitalocean-region=#{Config.worker.region} \
                        --digitalocean-image=#{Config.worker.image} \
                        --digitalocean-private-networking=true \
                        --swarm \
                        #{options[:master] ? '--swarm-master ' : ''} \
                        --swarm-discovery consul://#{kvip}:8500 \
                        --engine-opt \"cluster-store consul://#{kvip}:8500\" \
                        --engine-opt \"cluster-advertise eth1:2376\" \
                          #{name}", allow_failure: true)
  end

  def create_target
    return if Config.benchmark_target.ip
    puts "Creating benchmark target"

    run("docker-machine create \
                        --driver=digitalocean \
                        --digitalocean-access-token=#{token} \
                        --digitalocean-size=#{Config.benchmark_target.size} \
                        --digitalocean-region=#{Config.benchmark_target.region} \
                        --digitalocean-image=#{Config.benchmark_target.image} \
                          bench-target", allow_failure: true)
    run("docker-machine scp files/setup_chat.sh bench-target:/root/setup_chat.sh")
    run("docker-machine ssh bench-target /root/setup_chat.sh")
  end

  def teardown
    machines = ['bench-kv-store', 'bench-master'] + (1..workers.to_i).map { |i| "bench-agent-#{i}" }
    run("docker-machine rm -f #{machines.join(' ')}")
  end

  def teardown_target
    return if Config.benchmark_target.ip
    run("docker-machine rm -f bench-target")
  end

  def write_config
    renderer = ERB.new(File.read('./files/docker-compose.yml.erb'), nil, '<>')
    File.open('docker-compose.yml', 'w') do |f|
      f.write(renderer.result(binding()))
    end

    target_ip = Config.benchmark_target.ip || run("docker-machine ip bench-target", streaming_output: false).strip
    renderer = ERB.new(File.read(Config.tsung.template), nil, '<>')
    File.open('tsung.xml', 'w') do |f|
      f.write(renderer.result(binding()))
    end
    run("docker-machine scp tsung.xml bench-master:/root/tsung.xml")
  end

  def info
    puts ""
    puts ""
    puts "Tsung controller: http://#{run("docker-machine ip bench-master", streaming_output: false).strip}:8091"
    puts "Phoenix chat application: http://#{Config.benchmark_target.ip || run("docker-machine ip bench-target", streaming_output: false).strip}:4000"
    puts ""
    puts "Run the following commands to start the benchmark:"
    puts ""
    puts "docker-machine ssh bench-target \"cd chat; MIX_ENV=prod PORT=4000 iex --name bench@127.0.0.1 --cookie 123 --erl '+P 5000000 -kernel inet_dist_listen_min 9001 inet_dist_listen_max 9001' -S mix phoenix.server\""
    puts "eval $(docker-machine env --swarm bench-master)"
    puts "docker-compose up"
    puts ""
  end

  private

  def run(cmd, streaming_output: true, allow_failure: false)
    (status, output) = Runner.open3(cmd, streaming_output)
    if status != 0
      msg = "Failure executing command '#{cmd}':\n#{output}"
      if allow_failure
        puts msg
      else
        raise msg
      end
    end
    output
  end

  def self.open3(command, streaming_output = true)
    output = ""
    print "\n" if streaming_output

    status = Open3.popen3(ENV, "#{command} 2>&1") do |stdin, stdout, _stderr, wait_thr|
      stdin.close

      until stdout.eof do
        next unless IO.select([stdout])
        data = stdout.read_nonblock(1024)
        print data if streaming_output
        output << data
      end
      wait_thr.value
    end
    [status.exitstatus, output]
  rescue IOError => e
    return [1, "#{e} #{e.message}"]
  end
end
