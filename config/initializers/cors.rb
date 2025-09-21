Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins ENV.fetch("FRONTEND_ORIGIN", "*")
    resource "*",
             headers: :any,
             methods: [:get, :post, :options]
  end
end