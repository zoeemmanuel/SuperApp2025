SecureHeaders::Configuration.default do |config|
  config.cookies = {
    secure: true,
    httponly: SecureHeaders::OPT_OUT,  # Changed to OPT_OUT
    samesite: {
      none: true
    }
  }
  
  config.x_frame_options = "DENY"
  config.x_content_type_options = "nosniff"
  config.x_xss_protection = "1; mode=block"
  config.x_download_options = "noopen"
  config.x_permitted_cross_domain_policies = "none"
  config.referrer_policy = %w(origin-when-cross-origin strict-origin-when-cross-origin)
  
  # CSP settings
  config.csp = {
    default_src: %w('self'),
    script_src: %w('self' 'unsafe-inline' https://cdn.tailwindcss.com https://unpkg.com),
    style_src: %w('self' 'unsafe-inline' https://cdn.tailwindcss.com),
    img_src: %w('self' data:),
    connect_src: %w('self' https://superappproject.com),
    font_src: %w('self'),
    base_uri: %w('self'),
    form_action: %w('self'),
    frame_ancestors: %w('none')
  }
end
