Rails.application.config.session_store :cookie_store, 
  key: '_superapp_session',
  domain: '.superappproject.com',
  secure: true,
  same_site: :none,  # Changed from :lax to :none
  httponly: false,   # Added this line
  expire_after: 1.year
