site :opscode

metadata

cookbook 'collectd', github: 'EfrainOlivares/chef-collectd', ref: 'ec50609ed6eb193e0411f30aced91befa571940f'
cookbook 'mysql', github: 'arangamani-cookbooks/mysql', branch: 'COOK-2100'
cookbook 'rightscale_tag', github: 'rightscale-cookbooks/rightscale_tag'

group :integration do
  cookbook 'apt', '~> 2.3.0'
  cookbook 'yum', '~> 2.4.2'
  cookbook 'fake', path: './test/cookbooks/fake'
end
