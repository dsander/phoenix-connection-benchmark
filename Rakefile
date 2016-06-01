require './lib/config'
require './lib/runner'

task :check do
  if !ENV['DO_TOKEN'] && !Config.digital_ocean_token
    puts "Please set your Digital Ocean API docker in DO_TOKEN or config.yml"
    exit
  end
  unless Config.workers
    puts "Please set the amount of tsung workers in config.yml"
    exit
  end
end

desc "Setup tsung cluster"
task :setup_cluster => [:check] do
  runner = Runner.new
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
  runner = Runner.new
  runner.teardown
end

desc "Setup benchmark target"
task :setup_target => [:check] do
  puts "Creating benchmark target machine ..."
  runner = Runner.new
  runner.create_target
end

desc "Teardown benchmark target"
task :teardown_target => [:check] do
  puts "Removing benchmark target machine ...."
  runner = Runner.new
  runner.teardown_target
end

multitask :setup_all => [:setup_cluster, :setup_target] do
  puts "Sawrm cluster and benchmark target are set up."
end

desc "Update and upload config files"
task :update_config => [:check] do
  runner = Runner.new
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
