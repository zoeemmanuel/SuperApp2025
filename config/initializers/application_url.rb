Rails.application.config.after_initialize do
  Rails.application.routes.default_url_options[:host] = case Rails.env
    when 'production'
      'superappproject.com'
    else
      'localhost:3000'
  end

  Rails.application.routes.default_url_options[:protocol] = 'https'
end
