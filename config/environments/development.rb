require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.enable_reloading = true
  config.eager_load = false
  config.consider_all_requests_local = true
  config.server_timing = true

  # Configure caching - use memory store with larger size
  config.action_controller.perform_caching = true
  config.cache_store = :memory_store, { size: 64.megabytes }
  config.public_file_server.headers = {
    "Cache-Control" => "public, max-age=#{2.days.to_i}"
  }

  config.active_storage.service = :local
  config.action_mailer.raise_delivery_errors = false
  config.action_mailer.perform_caching = false
  config.action_mailer.default_url_options = { host: "localhost", port: 3000 }
  config.active_support.deprecation = :log
  config.active_record.migration_error = :page_load
  config.active_record.verbose_query_logs = true
  config.active_record.query_log_tags_enabled = true
  config.active_job.verbose_enqueue_logs = true
  config.action_view.annotate_rendered_view_with_filenames = true
  config.action_controller.raise_on_missing_callback_actions = true
  
  # Allow remote connections to console
  config.web_console.allowed_ips = ['0.0.0.0/0']
  
  # Allow specific hosts
  config.hosts.clear
  config.hosts << "superappproject.com"
  config.hosts << "www.superappproject.com"
  config.hosts << "localhost"

  # Enable session store with domain support
  config.session_store :cookie_store, 
    key: '_superapp_session',
    domain: '.superappproject.com',
    expire_after: 30.days,
    secure: true,
    same_site: :lax
end
