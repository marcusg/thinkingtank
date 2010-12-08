require 'thinkingtank/indextank_client'

module ThinkingTank
    class Builder
        def initialize(model, &block)
            @index_fields = []
            self.instance_eval &block
        end
        def indexes(*args)
            options = args.extract_options!
            args.each do |field|
                @index_fields << field
            end
        end
        def index_fields
            return @index_fields
        end
        def method_missing(method)
            return method
        end
    end
    class Configuration
        include Singleton
        attr_accessor :app_root, :client
        def initialize
            self.app_root = RAILS_ROOT if defined?(RAILS_ROOT)
            self.app_root = Merb.root  if defined?(Merb)
            self.app_root ||= Dir.pwd

            path = "#{app_root}/config/indextank.yml"
            return unless File.exists?(path)

            conf = YAML::load(ERB.new(IO.read(path)).result)[environment]
            api_url = ENV['HEROKUTANK_API_URL'] || conf['api_url']
            self.client = IndexTank::ApiClient.new(api_url).get_index(conf['index_name'])
        end
        def environment
            if defined?(Merb)
                Merb.environment
            elsif defined?(RAILS_ENV)
                RAILS_ENV
            else
                ENV['RAILS_ENV'] || 'development'
            end
        end
    end
    
    module IndexMethods
        def update_index
            it = ThinkingTank::Configuration.instance.client
            docid = self.class.name + ' ' + self.id.to_s
            data = {}
            self.class.thinkingtank_builder.index_fields.each do |field|
                val = self.instance_eval(field.to_s)
                data[field.to_s] = val.to_s unless val.nil?
            end
            data[:__any] = data.values.join " . "
            data[:__type] = self.class.name
            it.add_document(docid, data)
        end
    end

end

class << ActiveRecord::Base
    @indexable = false
    def search(*args)
        return indextank_search(true, *args)
    end
    def search_raw(*args)
        return indextank_search(false, *args)
    end

    def define_index(name = nil, &block)
        include ThinkingTank::IndexMethods
        @thinkingtank_builder = ThinkingTank::Builder.new self, &block
        @indexable = true
        after_save :update_index
    end

    def is_indexable?
        return @indexable
    end

    def thinkingtank_builder
        return @thinkingtank_builder
    end
    
    private
    
    def indextank_search(models, *args)
        options = args.extract_options!
        query = args.join(' ')
        
        # transform fields in query
        
        if options.has_key? :conditions
            options[:conditions].each do |field,value|
                query += " #{field}:(#{value})"
            end
        end
        
        options.slice!(:snippet, :fetch, :function)

        it = ThinkingTank::Configuration.instance.client
        models = []
        res = it.search("__any:(#{query.to_s}) __type:#{self.name}", options)
        if models
            res['results'].each do |doc|
                type, docid = doc['docid'].split(" ", 2)
                models << self.find(id=docid)
            end
            return models
        else
            res['results'].each do |doc|
                type, docid = doc['docid'].split(" ", 2)
                doc['model'] = self.find(id=docid)
            end
            return res
        end
    end

end


