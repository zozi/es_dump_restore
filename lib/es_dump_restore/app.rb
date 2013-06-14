require "es_dump_restore/es_client"
require "es_dump_restore/dumpfile"
require "thor"
require "progress_bar"
require "multi_json"

module EsDumpRestore
  class App < Thor

    desc "dump URL INDEX_NAME FILENAME", "Creates a dumpfile based on the given ElasticSearch index"
    def dump(url, index_name, filename)
      client = EsClient.new(url, index_name)

      Dumpfile.write(filename) do |dumpfile|
        dumpfile.index = {
          settings: client.settings,
          mappings: client.mappings
        }

        client.start_scan do |scroll_id, total|
          dumpfile.num_objects = total
          bar = ProgressBar.new(total)

          dumpfile.get_objects_output_stream do |out|
            client.each_scroll_hit(scroll_id) do |hit|
              metadata = { index: { _type: hit["_type"], _id: hit["_id"] } }
              out.write("#{MultiJson.dump(metadata)}\n#{MultiJson.dump(hit["_source"])}\n")
              bar.increment!
            end
          end
        end
      end
    end

    desc "restore URL INDEX_NAME FILENAME", "Restores a dumpfile into the given ElasticSearch index"
    def restore(url, index_name, filename)
      client = EsClient.new(url, index_name)

      Dumpfile.read(filename) do |dumpfile|
        client.create_index(dumpfile.index)

        bar = ProgressBar.new(dumpfile.num_objects)
        dumpfile.scan_objects(1000) do |batch, size|
          client.bulk_index batch
          bar.increment!(size)
        end
      end
    end

    no_commands do
      # not command line access: use this to load the data in memory and recreate the
      # index later
      def load_data(url, index_name, filename)
        @url = url
        @index_name = index_name
        @data = ""
        client = EsClient.new(url, index_name)
        Dumpfile.read(filename) do |dumpfile|
          @index = dumpfile.index
          bar = ProgressBar.new(dumpfile.num_objects)
          dumpfile.scan_objects(1000) do |batch, size|
            @data += batch
            bar.increment!(size)
          end
        end
      end

      # You should delete the index before running this...
      # load the dump data into the index
      def recreate!
        client = EsClient.new(@url, @index_name)
        client.create_index(@index)
        client.bulk_index(@data)
      end
    end
  end
end