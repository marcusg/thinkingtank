require 'thinkingtank/init'
require 'active_record'

class << ActiveRecord::Base
    @indexable = false

    # renamed because of naming conflicts with meta_search for example
    def search_tank(*args)
        return indextank_search(true, *args)
    end
    def search_tank_raw(*args)
        return indextank_search(false, *args)
    end

    # defining aliases in case of no conflicting methods
    alias_method :search, :search_tank if not ActiveRecord::Base.respond_to? :search
    alias_method :search_raw, :search_tank_raw

    def define_index(name = nil, &block)
        include ThinkingTank::IndexMethods
        @thinkingtank_builder = ThinkingTank::Builder.new self, &block
        @indexable = true
        after_save :update_index
        before_destroy :delete_from_index
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

        # added :len as parameter option
        options.slice!(:snippet, :fetch, :function, :len)

        it = ThinkingTank::Configuration.instance.client

        res = it.search("__any:(#{query.to_s}) __type:#{self.name}", options)
        if models
            models = []
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

