require 'spec_helper'

mysql_name = ''
case backend.check_os[:family]
when 'Ubuntu'
  mysql_name = 'mysql'
  mysql_config_file = '/etc/mysql/my.cnf'
  mysql_server_packages = %w{mysql-server apparmor-utils}
when 'RedHat'
  mysql_name = 'mysqld'
  mysql_config_file = '/etc/my.cnf'
  mysql_server_packages = %w{mysql-server}
end

describe "MySQL server packages are installed" do
  mysql_server_packages.each do |pkg|
    describe package(pkg) do
      it { should be_installed }
    end
  end
end

describe service(mysql_name) do
  it { should be_enabled }
  it { should be_running }
end

describe port(3306) do
  it { should be_listening }
end

describe file(mysql_config_file) do
  it { should be_file }
end

describe "verify the tuning attributes set in #{mysql_config_file}" do
  {
    query_cache_size: "4M",
    innodb_buffer_pool_size: "392M",
    thread_cache_size: 50,
    max_connections: 800,
    wait_timeout: 28800,
    net_read_timeout: 30,
    net_write_timeout: 30,
    back_log: 128,
    max_heap_table_size: "32M",
    read_buffer_size: "1M",
    read_rnd_buffer_size: "4M",
    long_query_time: 5,
    key_buffer_size: "16M",
    max_allowed_packet: "20M",
    innodb_log_file_size: "4M",
    innodb_log_buffer_size: "16M",
    table_cache: 256,
    sort_buffer_size: "2M",
    innodb_additional_mem_pool_size: "50M",
    myisam_sort_buffer_size: "64M"
  }.each do |attribute, value|
    describe command("grep -E \"^#{attribute}\\s+\" #{mysql_config_file}") do
      it { should return_stdout /#{value}/ }
    end
  end
end

describe file('/var/lib/mysql') do
  it { should be_directory }
end

describe "can run MySQL queries on the server" do
  describe "'app_test' database exists" do
    describe command(
      "echo \"SHOW DATABASES LIKE 'app_test'\" | mysql --user=root --password=rootpass"
    ) do
      it { should return_stdout /app_test/ }
    end
  end

  describe "select tables from a database" do
    describe command(
      "echo \"USE app_test; SELECT * FROM app_test\" | mysql --user=root --password=rootpass"
    ) do
      it { should return_stdout /I am in the db/ }
    end
  end

  describe "create database" do
    describe command(
      "echo \"CREATE DATABASE IF NOT EXISTS blah; SHOW DATABASES LIKE 'blah'\" | mysql --user=root --password=rootpass"
    ) do
      it { should return_stdout /blah/ }
    end
  end
end
