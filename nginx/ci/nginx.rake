require 'ci/common'

def nginx_version
  ENV['FLAVOR_VERSION'] || '1.7.11'
end

def nginx_rootdir
  "#{ENV['INTEGRATIONS_DIR']}/nginx_#{nginx_version}"
end

container_name = 'dd-test-nginx'
container_port1 = 44_441
container_port2 = 44_442

namespace :ci do
  namespace :nginx do |flavor|
    task before_install: ['ci:common:before_install'] do |t|
      sh %(docker kill #{container_name} 2>&1 >/dev/null || true 2>&1 >/dev/null)
      sh %(docker rm #{container_name} 2>&1 >/dev/null || true 2>&1 >/dev/null)
      t.reenable
    end

    task install: ['ci:common:install'] do |t|
      use_venv = in_venv
      install_requirements('nginx/requirements.txt',
                           "--cache-dir #{ENV['PIP_CACHE']}",
                           "#{ENV['VOLATILE_DIR']}/ci.log", use_venv)
      t.reenable
    end

    task :install_infrastructure do |t|
      if nginx_version == '1.6.2'
        repo = 'centos/nginx-16-centos7'
        sh %(docker create -p #{container_port1}:#{container_port1} -p #{container_port2}:#{container_port2} --name #{container_name} #{repo})
        sh %(docker cp #{__dir__}/nginx.conf #{container_name}:/opt/rh/nginx16/root/etc/nginx/nginx.conf)
        sh %(docker cp #{__dir__}/testing.key #{container_name}:/opt/rh/nginx16/root/etc/nginx/testing.key)
        sh %(docker cp #{__dir__}/testing.crt #{container_name}:/opt/rh/nginx16/root/etc/nginx/testing.crt)
        sh %(docker start #{container_name})
      else
        repo = "nginx:#{nginx_version}"
        volumes = %( -v #{__dir__}/nginx.conf:/etc/nginx/nginx.conf \
        -v #{__dir__}/testing.crt:/etc/nginx/testing.crt \
        -v #{__dir__}/testing.key:/etc/nginx/testing.key )
        sh %(docker run -d -p #{container_port1}:#{container_port1} -p #{container_port2}:#{container_port2} \
        --name #{container_name} #{volumes} #{repo})
      end
      t.reenable
    end

    task before_script: ['ci:common:before_script']

    task script: ['ci:common:script'] do |t|
      this_provides = [
        'nginx'
      ]
      Rake::Task['ci:common:run_tests'].invoke(this_provides)
      t.reenable
    end

    task before_cache: ['ci:common:before_cache']

    task cleanup: ['ci:common:cleanup'] do |t|
      sh %(docker kill #{container_name} 2>&1 >/dev/null || true 2>&1 >/dev/null)
      sh %(docker rm #{container_name} 2>&1 >/dev/null || true 2>&1 >/dev/null)
      t.reenable
    end

    task :execute do
      if ENV['FLAVOR_VERSION']
        flavor_versions = ENV['FLAVOR_VERSION'].split(',')
      else
        flavor_versions = [nil]
      end

      exception = nil
      begin
        %w(before_install install).each do |u|
          Rake::Task["#{flavor.scope.path}:#{u}"].invoke
        end
        flavor_versions.each do |flavor_version|
          section("TESTING VERSION #{flavor_version}")
          ENV['FLAVOR_VERSION'] = flavor_version
          %w(install_infrastructure before_script).each do |u|
            Rake::Task["#{flavor.scope.path}:#{u}"].invoke
          end
          Rake::Task["#{flavor.scope.path}:script"].invoke
          Rake::Task["#{flavor.scope.path}:before_cache"].invoke
          Rake::Task["#{flavor.scope.path}:cleanup"].invoke
        end
      rescue => e
        exception = e
        puts "Failed task: #{e.class} #{e.message}".red
      end
      if ENV['SKIP_CLEANUP']
        puts 'Skipping cleanup, disposable environments are great'.yellow
      else
        puts 'Cleaning up'
        Rake::Task["#{flavor.scope.path}:cleanup"].invoke
      end
      raise exception if exception
    end
  end
end
