Rails.application.config.action_dispatch.cookies_same_site_protection = :none
Rails.application.config.action_dispatch.cookies_serializer = :json
Rails.application.config.action_dispatch.use_cookies_with_metadata = true

Rails.application.config.session_options = {
  secure: true,
  same_site: :none,
  domain: '.superappproject.com',
  httponly: false,
  expire_after: 1.year
}

Rails.application.config.action_dispatch.cookies_rotations.tap do |cookies|
  cookies.rotate :signed
  cookies.rotate :encrypted
end
