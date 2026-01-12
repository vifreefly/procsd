require_relative "container_helper"

World(ContainerHelper)

Before do
  @container = ContainerHelper::Container.new
  @container.start
end

After do
  @container&.stop
end
