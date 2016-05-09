module Jwt
  class ContainerRegistryAuthenticationService < BaseService
    AUDIENCE = 'container_registry'

    def execute
      if params[:offline_token]
        return error('forbidden', 403) unless current_user
      end

      return error('forbidden', 401) if scopes.empty?

      { token: authorized_token(scopes).encoded }
    end

    def self.full_access_token(*names)
      registry = Gitlab.config.registry
      token = ::Jwt::RSAToken.new(registry.key)
      token.issuer = registry.issuer
      token.audience = AUDIENCE
      token[:access] = names.map do |name|
        { type: 'repository', name: name, actions: %w(pull push) }
      end
      token.encoded
    end

    private

    def authorized_token(access)
      token = ::Jwt::RSAToken.new(registry.key)
      token.issuer = registry.issuer
      token.audience = AUDIENCE
      token.subject = current_user.try(:username)
      token[:access] = access
      token
    end

    def scopes
      return unless params[:scope]

      @scopes ||= begin
        scope = process_scope(params[:scope])
        [scope].compact
      end
    end

    def process_scope(scope)
      type, name, actions = scope.split(':', 3)
      actions = actions.split(',')

      case type
      when 'repository'
        process_repository_access(type, name, actions)
      end
    end

    def process_repository_access(type, name, actions)
      requested_project = Project.find_with_namespace(name)
      return unless requested_project

      actions = actions.select do |action|
        can_access?(requested_project, action)
      end

      { type: type, name: name, actions: actions } if actions.present?
    end

    def can_access?(requested_project, requested_action)
      case requested_action
      when 'pull'
        requested_project.public? || requested_project == project || can?(current_user, :read_container_registry, requested_project)
      when 'push'
        requested_project == project || can?(current_user, :create_container_registry, requested_project)
      else
        false
      end
    end

    def registry
      Gitlab.config.registry
    end
  end
end
