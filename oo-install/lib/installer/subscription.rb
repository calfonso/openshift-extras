require 'installer/helpers'

module Installer
  class Subscription
    include Installer::Helpers

    @repo_attrs = [:repos_base, :jboss_repo_base, :jenkins_repo_base, :scl_repo, :os_repo, :os_optional_repo, :puppet_repo_rpm]
    @object_attrs = [:subscription_type, :rh_username, :rh_password, :sm_reg_pool, :rhn_reg_actkey].concat(@repo_attrs)

    attr_reader :config, :type
    attr_accessor *@object_attrs

    class << self
      def object_attrs
        @object_attrs
      end

      def repo_attrs
        @repo_attrs
      end

      def subscription_info(type)
        case type
        when :none
          return {
            :desc => 'No subscription necessary',
            :attrs => {},
            :attr_order => [],
          }
        when :yum
          return {
            :desc => 'Get packages from yum and do not use a subscription',
            :attrs => {
              :repos_base => 'The base URL for the OpenShift repositories',
              :jboss_repo_base => 'The base URL for a JBoss repository',
              :jenkins_repo_base => 'The base URL for a Jenkins repository',
              :scl_repo => 'The base URL for an SCL repository',
              :os_repo => 'The URL of a yum repository for the operating system',
              :os_optional_repo => 'The URL for an "Optional" repository for the operating system',
              :puppet_repo_rpm => 'The URL for a Puppet Labs repository RPM',
            },
            :attr_order => repo_attrs,
          }
        when :rhsm
          return {
            :desc => 'Use Red Hat Subscription Manager',
            :attrs => {
              :rh_username => 'Red Hat Login username',
              :rh_password => 'Red Hat Login password',
              :sm_reg_pool => 'Pool ID(s) to subscribe',
            },
            :attr_order => [:rh_username,:rh_password,:sm_reg_pool],
          }
        when :rhn
          return {
            :desc => 'Use Red Hat Network',
            :attrs => {
              :rh_username => 'Red Hat Login username',
              :rh_password => 'Red Hat Login password',
              :rhn_reg_actkey => 'RHN account activation key',
            },
            :attr_order => [:rh_username,:rh_password,:rhn_reg_actkey],
          }
        else
          raise Installer::SubscriptionTypeNotRecognizedException.new("Subscription type '#{type}' is not recognized.")
        end
      end

      def valid_attr? attr, value, check=:basic
        errors = []
        if attr == :subscription_type
          begin
            subscription_info(value)
          rescue Installer::SubscriptionTypeNotRecognizedException => e
            if check == :basic
              return false
            else
              errors << e
            end
          end
        elsif not attr == :subscription_type and not value.nil?
          # We have to be pretty flexible here, so we basically just format-check the non-nil values.
          if (@repo_attrs.include?(attr) and not is_valid_url?(value)) or
             ([:rh_username, :rh_password, :sm_reg_pool, :rhn_reg_actkey].include?(attr) and not is_valid_string?(value))
            return false if check == :basic
            errors << Installer::SubscriptionSettingNotValidException.new("Subscription setting '#{attr.to_s}' has invalid value '#{value}'.")
          end
        end
        return true if check == :basic
        errors
      end

      def valid_types_for_context
        case get_context
        when :origin, :origin_vm
          return [:none,:yum]
        when :ose
          return [:none,:yum,:rhsm,:rhn]
        else
          raise Installer::UnrecognizedContextException.new("Installer context '#{get_context}' is not supported.")
        end
      end
    end

    def initialize config, subscription={}
      @config = config
      self.class.object_attrs.each do |attr|
        attr_str = attr == :subscription_type ? 'type' : attr.to_s
        if subscription.has_key?(attr_str)
          value = attr == :subscription_type ? subscription[attr_str].to_sym : subscription[attr_str]
          self.send("#{attr.to_s}=".to_sym, value)
        end
      end
    end

    def subscription_types
      @subscription_types ||=
        begin
          type_map = {}
          self.class.valid_types_for_context.each do |type|
            type_map[type] = self.class.subscription_info(type)
          end
          type_map
        end
    end

    def is_valid?(check=:basic)
      errors = []
      if subscription_type.nil?
        return false if check == :basic
        errors << Installer::SubscriptionSettingMissingException.new("The subscription type value is missing for the configuration.")
      end
      if not [:none,:yum].include?(subscription_type)
        # The other subscription types require username and password
        self.class.subscription_info(subscription_type)[:attrs].each_key do |attr|
          next if not [:rh_username,:rh_password].include?(attr)
          if self.send(attr).nil?
            return false if check == :basic
            errors << Installer::SubscriptionSettingMissingException.new("The #{attr.to_s} value is missing, but it is required for supscription type #{subscription_type.to_s}.")
          end
        end
      end
      self.class.object_attrs.each do |attr|
        if check == :basic
          return false if not self.class.valid_attr?(attr, self.send(attr), check)
        else
          errors.concat(self.class.valid_attr?(attr, self.send(attr), check))
        end
      end
      return true if check == :basic
      errors
    end

    def to_hash
      export_hash = {}
      self.class.object_attrs.each do |attr|
        value = self.send(attr)
        if not value.nil?
          key = attr.to_s
          if attr == :subscription_type
            key = 'type'
            value = value.to_s
          end
          export_hash[key] = value
        end
      end
      export_hash
    end
  end
end
