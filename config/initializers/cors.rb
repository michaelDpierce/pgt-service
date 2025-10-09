Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins "http://localhost:3001", ENV.fetch("FRONTEND_ORIGIN", "*")
    resource "*", headers: :any, methods: %i[get post options], credentials: true

  end
end