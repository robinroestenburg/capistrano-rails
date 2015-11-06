module Capistrano
  class FileNotFound < StandardError
  end
end

namespace :deploy do
  before :starting, :set_shared_assets do
    set :linked_dirs, (fetch(:linked_dirs) || []).push('public/assets')
  end

  desc 'Normalise asset timestamps'
  task :normalise_assets do
    on roles :web do
      assets = fetch(:normalize_asset_timestamps)
      if assets
        within release_path do
          execute :find, "#{assets} -exec touch -t #{asset_timestamp} {} ';'; true"
        end
      end
    end
  end

  desc 'Compile assets'
  task :compile_assets do
    invoke 'deploy:assets:precompile'
    invoke 'deploy:assets:backup_manifest'
  end

  # FIXME: it removes every asset it has just compiled
  desc 'Cleanup expired assets'
  task :cleanup_assets do
    on roles :web do
      within release_path do
        with rails_env: fetch(:rails_env) do
          execute :rake, "assets:clean"
        end
      end
    end
  end

  desc 'Rollback assets'
  task :rollback_assets do
    begin
      invoke 'deploy:assets:restore_manifest'
    rescue Capistrano::FileNotFound
      invoke 'deploy:compile_assets'
    end
  end

  after 'deploy:updated', 'deploy:compile_assets'
  # NOTE: we don't want to remove assets we've just compiled
  # after 'deploy:updated', 'deploy:cleanup_assets'
  after 'deploy:updated', 'deploy:normalise_assets'
  after 'deploy:reverted', 'deploy:rollback_assets'

  namespace :assets do
    task :precompile do
      on roles :web do
        within release_path do
          with rails_env: fetch(:rails_env) do
            execute :rake, "assets:precompile"
          end
        end
      end
    end

    task :backup_manifest do
      on roles :web do
        within release_path do
          backup_path = release_path.join('assets_manifest_backup')

          execute :mkdir, '-p', backup_path
          execute :cp,
            detect_manifest_path,
            backup_path
        end
      end
    end

    task :restore_manifest do
      on roles :web do
        within release_path do
          source = release_path.join('assets_manifest_backup')
          target = detect_manifest_path
          if test "[[ -f #{source} && -f #{target} ]]"
            execute :cp, source, target
          else
            msg = 'Rails assets manifest file (or backup file) not found.'
            warn msg
            fail Capistrano::FileNotFound, msg
          end
        end
      end
    end

    def detect_manifest_path
      %w(.sprockets-manifest* manifest*.*).each do |pattern|
        candidate = release_path.join('public', 'assets', pattern)
        return capture(:ls, candidate).strip if test(:ls, candidate)
      end
      msg = 'Rails assets manifest file not found.'
      warn msg
      fail Capistrano::FileNotFound, msg
    end
  end
end
