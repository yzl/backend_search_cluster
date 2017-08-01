#
# Cookbook:: backend_search_cluster
# Recipe:: search_es.rb
#
# Copyright:: 2017, The Authors, All Rights Reserved.

include_recipe 'sysctl::apply'

include_recipe 'java'

elasticsearch_user 'elasticsearch'

directory '/var/run/elasticsearch' do
  action :create
  recursive true
  owner 'elasticsearch'
  group 'elasticsearch'
end

elasticsearch_config = {
  'cluster.name' => node['elasticsearch']['cluster_name'] || 'elasticsearch',
  'node.name' => node['hostname'],
  'network.host' => node['ipaddress'],
  'discovery.type' => 'ec2',
  'cloud.aws.region' => node['aws']['region'],
  'http.max_content_length' => node['elasticsearch']['es_max_content_length']
}

elasticsearch_install 'elasticsearch' do
  type 'tarball' # type of install
  dir  '/opt/' # where to install
  version '5.4.1'
  action :install # could be :remove as well
end

half_system_ram = (node['memory']['total'].to_i * 0.5).floor / 1024

elasticsearch_configure 'elasticsearch' do
  # if you override one of these, you probably want to override all
  path_home     '/opt/elasticsearch'
  path_conf     '/etc/elasticsearch'
  path_data     '/var/opt/elasticsearch'
  path_logs     '/var/log/elasticsearch'
  path_pid      '/var/run/elasticsearch'
  path_plugins  '/opt/elasticsearch/plugins'
  path_bin      '/opt/elasticsearch/bin'
  logging(action: 'INFO')
  jvm_options %w( 
                -XX:+UseParNewGC
                -XX:+UseConcMarkSweepGC
                -XX:CMSInitiatingOccupancyFraction=75
                -XX:+UseCMSInitiatingOccupancyOnly
                -XX:+HeapDumpOnOutOfMemoryError
                -XX:+PrintGCDetails
                -server
                -Xss1m
                -Djava.awt.headless=true
                -Dfile.encoding=UTF-8
                -Djna.nosys=true
                -Djdk.io.permissionsUseCanonicalPath=true
                -Dio.netty.noUnsafe=true
                -Dio.netty.noKeySetOptimization=true
                -Dio.netty.recycler.maxCapacityPerThread=0
                -Dlog4j.shutdownHookEnabled=false
                -Dlog4j2.disable.jmx=true
                -Dlog4j.skipJansi=true
              )
  configuration elasticsearch_config
  action :manage
  notifies :restart, 'service[elasticsearch]', :delayed
end

%w(/opt/elasticsearch/plugins /opt/elasticsearch/plugins/discovery-ec2 /opt/elasticsearch/plugins/repository-s3 ).each do |dir|
  directory dir do
    owner 'elasticsearch'
    group 'elasticsearch'
  end
end

elasticsearch_plugin 'discovery-ec2' do
  action :install
end

elasticsearch_plugin 'repository-s3' do
  action :install
end

link '/opt/elasticsearch/elasticsearch' do
  to '/etc/sysconfig/elasticsearch'
end

elasticsearch_service 'elasticsearch' do
  action :nothing
end

template '/usr/lib/systemd/system/elasticsearch.service' do
  owner 'root'
  mode '0644'
  source 'systemd_unit.erb'
  variables(
    # we need to include something about #{progname} fixed in here.
    program_name: 'elasticsearch',
    default_dir: '/opt/elasticsearch',
    path_home: '/opt/elasticsearch',
    es_user: 'elasticsearch',
    es_group: 'elasticsearch',
    nofile_limit: '65536'
  )
  notifies :restart, 'service[elasticsearch]', :immediately
end

service 'elasticsearch' do
  action [:enable, :start]
end
