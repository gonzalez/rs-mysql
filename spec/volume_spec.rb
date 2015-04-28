require_relative 'spec_helper'

describe 'rs-mysql::volume' do
  let(:chef_runner) do
    ChefSpec::Runner.new(platform: 'ubuntu', version: '12.04') do |node|
      node.set['cloud']['private_ips'] = ['10.0.2.15']
      node.set['memory']['total'] = '1011228kB'
      node.set['rightscale_volume']['data_storage']['device'] = '/dev/sda'
      node.set['rightscale_backup']['data_storage']['devices'] = ['/dev/sda']
      node.set['rs-mysql']['backup']['lineage'] = 'testing'
      node.set['rs-mysql']['server_repl_password'] = 'replpass'
      node.set['rs-mysql']['server_root_password'] = 'rootpass'
    end
  end
  let(:nickname) { chef_run.node['rs-mysql']['device']['nickname'] }
  let(:new_mysql_dir) {"/mnt/storage/mysql"}
  let(:detach_timeout) do
    chef_runner.converge(described_recipe).node['rs-mysql']['device']['detach_timeout'].to_i
  end

  before do
    stub_command('[ `rs_config --get decommission_timeout` -eq 300 ]').and_return(false)
    stub_command("/usr/bin/mysql -u root -e 'show databases;'").and_return(true)
    stub_command("chown --recursive --silent mysql:mysql #{new_mysql_dir}").and_return(true)
    stub_command("stat -c %U #{new_mysql_dir}/mysql |grep mysql").and_return(false)
  end

  context 'rs-mysql/restore/lineage is not set' do
    let(:chef_run) { chef_runner.converge(described_recipe) }

    it 'sets the decommission timeout' do
      expect(chef_run).to run_execute("set decommission timeout to #{detach_timeout}").with(
        command: "rs_config --set decommission_timeout #{detach_timeout}",
      )
    end

    it 'creates a new volume and attaches it' do
      expect(chef_run).to create_rightscale_volume(nickname).with(
        size: 10,
        options: {},
      )
      expect(chef_run).to attach_rightscale_volume(nickname)
    end

    it 'formats the volume and mounts it' do
      expect(chef_run).to create_filesystem(nickname).with(
        fstype: 'ext4',
        mkfs_options: '-F',
        mount: '/mnt/storage',
      )
      expect(chef_run).to enable_filesystem(nickname)
      expect(chef_run).to mount_filesystem(nickname)
    end

    it 'creates the MySQL directory on the volume' do
      expect(chef_run).to create_directory('/mnt/storage/mysql').with(
        owner: 'mysql',
        group: 'mysql',
      )
    end

    it 'recursively changes ownership of the mysql directory' do
      expect(chef_run).to run_execute("change permissions #{new_mysql_dir} owner").with(
        command: "chown --recursive --silent mysql:mysql #{new_mysql_dir}"
      )
    end

    it 'overrides the MySQL directory attributes' do
      expect(chef_run.node['mysql']['data_dir']).to eq('/mnt/storage/mysql')
      expect(chef_run.node['mysql']['server']['directories']['log_dir']).to eq('/mnt/storage/mysql')
    end

    it 'includes the default recipe' do
      expect(chef_run).to include_recipe('rs-mysql::default')
    end

    context 'iops is set to 100' do
      let(:chef_run) do
        chef_runner.node.set['rs-mysql']['device']['iops'] = 100
        chef_runner.converge(described_recipe)
      end

      it 'creates a new volume with iops set to 100 and attaches it' do
        expect(chef_run).to create_rightscale_volume(nickname).with(
          size: 10,
          options: {iops: 100},
        )
        expect(chef_run).to attach_rightscale_volume(nickname)
      end
    end
  end

  context 'rs-mysql/restore/lineage is set' do
    let(:chef_runner_restore) do
      chef_runner.node.set['rs-mysql']['restore']['lineage'] = 'testing'
      chef_runner
    end
    let(:chef_run) do
      chef_runner_restore.converge(described_recipe)
    end
    let(:device) { chef_run.node['rightscale_volume'][nickname]['device'] }

    it 'creates a volume from the backup' do
      expect(chef_run).to restore_rightscale_backup(nickname).with(
        lineage: 'testing',
        timestamp: nil,
        size: 10,
        options: {},
      )
    end

    it 'mounts and enables the restored volume' do
      expect(chef_run).to mount_mount(device).with(
        fstype: 'ext4',
      )
      expect(chef_run).to enable_mount(device)
    end

    it 'deletes the old MySQL directory' do
      expect(chef_run).to delete_directory('/var/lib/mysql').with(
        recursive: true,
      )
    end

    it 'creates the MySQL directory symlink' do
      expect(chef_run).to create_link('/var/lib/mysql').with(
        to: '/mnt/storage/mysql',
      )
    end

    it 'creates the MySQL directory on the volume' do
      expect(chef_run).to create_directory('/mnt/storage/mysql').with(
        owner: 'mysql',
        group: 'mysql',
      )
    end

    it 'overrides the MySQL directory attributes' do
      expect(chef_run.node['mysql']['data_dir']).to eq('/mnt/storage/mysql')
      expect(chef_run.node['mysql']['server']['directories']['log_dir']).to eq('/mnt/storage/mysql')
    end

    it 'includes the default recipe' do
      expect(chef_run).to include_recipe('rs-mysql::default')
    end

    context 'iops is set to 100' do
      let(:chef_run) do
        chef_runner_restore.node.set['rs-mysql']['device']['iops'] = 100
        chef_runner_restore.converge(described_recipe)
      end

      it 'creates a volume from the backup with iops' do
        expect(chef_run).to restore_rightscale_backup(nickname).with(
          lineage: 'testing',
          timestamp: nil,
          size: 10,
          options: {iops: 100},
        )
      end
    end

    context 'timestamp is set' do
      let(:timestamp) { Time.now.to_i }
      let(:chef_run) do
        chef_runner_restore.node.set['rs-mysql']['restore']['timestamp'] = timestamp
        chef_runner_restore.converge(described_recipe)
      end

      it 'creates a volume from the backup with the timestamp' do
        expect(chef_run).to restore_rightscale_backup(nickname).with(
          lineage: 'testing',
          timestamp: timestamp,
          size: 10,
          options: {},
        )
      end
    end
  end
end
