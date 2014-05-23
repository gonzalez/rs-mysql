#
# Cookbook Name:: rs-mysql
# Recipe:: dump_import
#
# Copyright (C) 2014 RightScale, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

marker 'recipe_start_rightscale' do
  template 'rightscale_audit_entry.erb'
end

# Install git client
include_recipe 'git'

# Set temporary file locations.
key_file = "/tmp/git_key"
ssh_wrapper = "/tmp/git_ssh.sh"
destination_dir = "/tmp/git_download"

ssh_private_key = node['rs-mysql']['import']['private_key']

if ssh_private_key
  # Create private key file
  file key_file do
    owner "root"
    group "root"
    mode "0700"
    content ssh_private_key
    action :create
  end

  # Create bash script to use for GIT_SSH
  bash_script = %Q{exec ssh -o StrictHostKeyChecking=no -i #{key_file} "$@"}

  # Create wrapper script used if private key was provided
  file ssh_wrapper do
    owner "root"
    group "root"
    mode "0700"
    content bash_script
    action :create
  end
end

# Download from repository
git destination_dir do
  repository node['rs-mysql']['import']['repository']
  revision node['rs-mysql']['import']['revision']
  ssh_wrapper ssh_wrapper if ssh_private_key
end

# Immediatly delete sensitive temporary files
[key_file, ssh_wrapper].each do |filename|
  file filename do
    action :delete
    only_if ssh_private_key
  end
end

dump_file = ::File.join(destination_dir, node['rs-mysql']['import']['dump_file'])

touch_file = "/var/lib/rightscale/rs-mysql-import-#{::File.basename(dump_file)}.touch"

if ::File.exists?(touch_file)
  log "The dump file was already imported at #{::File.ctime(touch_file)}"
else
  case dump_file
  when /\.gz$/
    uncompress_command = "gunzip --stdout '#{dump_file}'"
  when /\.bz2$/
    uncompress_command = "bunzip2 --stdout '#{dump_file}'"
  when /\.xz$/
    uncompress_command = "xz --decompress --stdout '#{dump_file}'"
  end

  # The connection hash to use to connect to MySQL
  mysql_connection_info = {
    :host => 'localhost',
    :username => 'root',
    :password => node['rs-mysql']['server_root_password']
  }

  # Import from MySQL dump
  mysql_database ::File.basename(dump_file) do
    connection mysql_connection_info
    sql do
      if uncompress_command
        uncompress = Mixlib::ShellOut.new(uncompress_command).run_command
        uncompress.error!
        uncompress.stdout
      else
        ::File.read(dump_file)
      end
    end
    action :query
  end

  # Make sure directory /var/lib/rightscale exists which will contain the touch file
  directory '/var/lib/rightscale' do
    mode 0755
    recursive true
    action :create
  end

  # Create a touch file containing the name of the dump file so this action can be skipped if the
  # recipe is run with the same input multiple times.
  file touch_file do
    action :touch
  end
end

# After importing dump file, remove whole downloaded destination directory.
directory destination_dir do
  recursive true
  action :delete
end
