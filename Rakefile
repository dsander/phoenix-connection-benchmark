require 'open3'
require 'erb'

task :check do
  unless ENV['DO_TOKEN']
    puts "Please set your Digital Ocean API docker in DO_TOKEN"
    exit
  end
  unless ENV['WORKERS']
    puts "Please set the amount of tsung workers in WORKERS"
    exit
  end
end

class Runner
  attr_reader :token, :workers, :kvip

  def initialize(token = nil, workers=nil)
    @token = token
    @workers = workers.to_i
  end

  def create_consul
    puts "Creating consul container ..."
    run("docker-machine create \
                        --driver=digitalocean \
                        --digitalocean-access-token=#{token} \
                        --digitalocean-size=512mb \
                        --digitalocean-region=fra1 \
                        --digitalocean-private-networking=true \
                        --digitalocean-image=ubuntu-14-04-x64 \
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
                        --digitalocean-size=4gb \
                        --digitalocean-region=fra1 \
                        --digitalocean-private-networking=true \
                        --digitalocean-image=ubuntu-14-04-x64 \
                        --swarm \
                        #{options[:master] ? '--swarm-master ' : ''} \
                        --swarm-discovery consul://#{kvip}:8500 \
                        --engine-opt \"cluster-store consul://#{kvip}:8500\" \
                        --engine-opt \"cluster-advertise eth1:2376\" \
                          #{name}")
  end

  def create_target
    run("docker-machine create \
                        --driver=digitalocean \
                        --digitalocean-access-token=#{token} \
                        --digitalocean-size=64gb \
                        --digitalocean-region=fra1 \
                        --digitalocean-image=ubuntu-14-04-x64 \
                          bench-target")
    run("docker-machine scp files/setup_chat.sh bench-target:/root/setup_chat.sh")
    run("docker-machine ssh bench-target /root/setup_chat.sh")
  end

  def teardown
    machines = ['bench-kv-store', 'bench-master'] + (1..workers.to_i).map { |i| "bench-agent-#{i}" }
    run("docker-machine rm -f #{machines.join(' ')}")
  end

  def teardown_target
    run("docker-machine rm -f bench-target")
  end

  def write_config
    renderer = ERB.new(File.read('./files/docker-compose.yml.erb'), nil, '<>')
    File.open('docker-compose.yml', 'w') do |f|
      f.write(renderer.result(binding()))
    end

    target_ip = run("docker-machine ip bench-target", streaming_output: false).strip
    renderer = ERB.new(File.read('./files/tsung.xml.erb'), nil, '<>')
    File.open('tsung.xml', 'w') do |f|
      f.write(renderer.result(binding()))
    end
    run("docker-machine scp tsung.xml bench-master:/root/tsung.xml")
  end

  def info
    puts "Tsung controller: http://#{run("docker-machine ip bench-master", streaming_output: false).strip}:8091"
    puts "Phoenix chat application: http://#{run("docker-machine ip bench-target", streaming_output: false).strip}:4000"
    puts ""
    puts "Run the following commands to start the benchmark:"
    puts ""
    puts 'docker-machine ssh bench-target "cd chat; MIX_ENV=prod PORT=4000 ELIXIR_ERL_OPTS="+P 10000000" mix phoenix.server"'
    puts "eval $(docker-machine env --swarm bench-master)"
    puts "docker-compose up"
    puts ""
  end

  def run(cmd, streaming_output: true)
    (status, output) = Runner.open3(cmd, streaming_output)
    if status != 0
      raise "Failure executing command '#{cmd}':\n#{output}"
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

desc "Setup tsung cluster"
task :setup_cluster => [:check] do
  runner = Runner.new(ENV['DO_TOKEN'], ENV['WORKERS'])
  puts "Settting up docker tsung swarm cluster with #{runner.workers} workers ..."

  runner.create_consul

  runner.create_cluster

  runner.run("eval $(docker-machine env --swarm bench-master)")
  puts "Cluster created make sure to configure docker to connect to the swarm master:"
  puts "eval $(docker-machine env --swarm bench-master)"
end

desc "Teardown tsung cluster"
task :teardown_cluster => [:check] do
  puts "Removing swarm cluster"
  runner = Runner.new(ENV['DO_TOKEN'], ENV['WORKERS'])
  runner.teardown
end

desc "Setup benchmark target"
task :setup_target => [:check] do
  puts "Creating benchmark target machine ..."
  runner = Runner.new(ENV['DO_TOKEN'])
  runner.create_target
end

desc "Teardown benchmark target"
task :teardown_target => [:check] do
  puts "Removing benchmark target machine ...."
  runner = Runner.new(ENV['DO_TOKEN'])
  runner.teardown_target
end

multitask :setup_all => [:setup_cluster, :setup_target] do
  puts "Sawrm cluster and benchmark target are set up."
end

desc "Update and upload config files"
task :update_config => [:check] do
  runner = Runner.new(ENV['DO_TOKEN'], ENV['WORKERS'])
  runner.write_config
end

desc "Setup the tsung cluster and the benchmark target"
task :setup => [:setup_all, :update_config] do
  Runner.new.info
end

desc "Info"
task :info do
  Runner.new.info
end

desc "Teardown everything"
multitask :teardown => [:teardown_target, :teardown_cluster]
