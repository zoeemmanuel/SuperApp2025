Rails.application.configure do
  config.cache_classes = true
  config.eager_load = true
  config.consider_all_requests_local = false
  config.public_file_server.enabled = true
  config.force_ssl = true  # Enable SSL
  config.log_level = :info
  config.active_storage.service = :local
  config.serve_static_assets = true
  config.assets.compile = true
  config.active_record.dump_schema_after_migration = false
  
  # Session and cookie settings
  config.session_store :cookie_store, 
    key: '_superapp_session',
    domain: '.superappproject.com',
    secure: true,
    same_site: :lax
end
