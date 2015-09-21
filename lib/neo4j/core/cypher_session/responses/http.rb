require 'neo4j/core/cypher_session/responses'

module Neo4j
  module Core
    class CypherSession
      module Responses
        class HTTP < Base
          attr_reader :results, :request_data

          def initialize(faraday_response, request_data)
            @request_data = request_data

            validate_faraday_response!(faraday_response)

            @results = faraday_response.body[:results].map do |result_data|
              result_from_data(result_data[:columns], result_data[:data])
            end
          end

          def result_from_data(columns, entities_data)
            rows = entities_data.map do |entity_data|
              wrap_entity entity_data[:row], entity_data[:rest]
            end

            Result.new(columns, rows)
          end

          # TODO: Iterate over arrays and wrap elements within
          def wrap_entity(row_data, rest_data)
            row_data.each_with_index.map do |row_datum, i|
              rest_datum = rest_data[i]

              return wrap_entity(row_datum, rest_datum) if rest_datum.is_a?(Array)

              if rest_datum[:labels]
                wrap_node(rest_datum)
              elsif rest_datum[:type]
                wrap_relationship(rest_datum)
              elsif rest_datum[:start]
                wrap_path(row_datum, rest_datum)
              else
                row_datum
              end
            end
          end

          private

          def wrap_node(rest_datum)
            metadata_data = rest_datum[:metadata]
            ::Neo4j::Core::Node.new(id_from_rest_datum(rest_datum),
                                    metadata_data && metadata_data[:labels],
                                    rest_datum[:data]).wrap
          end

          def wrap_relationship(rest_datum)
            metadata_data = rest_datum[:metadata]
            ::Neo4j::Core::Relationship.new(id_from_rest_datum(rest_datum),
                                            metadata_data && metadata_data[:type],
                                            rest_datum[:data]).wrap
          end

          def wrap_path(row_datum, rest_datum)
            nodes = rest_datum[:nodes].each_with_index.map do |url, i|
              Node.from_url(url, row_datum[2 * i])
            end
            relationships = rest_datum[:relationships].each_with_index.map do |url, i|
              Relationship.from_url(url, row_datum[(2 * i) + 1])
            end

            ::Neo4j::Core::Path.new(nodes, relationships, rest_datum[:directions]).wrap
          end

          def id_from_rest_datum(rest_datum)
            if rest_datum[:metadata]
              rest_datum[:metadata][:id]
            else
              rest_datum[:self].split('/').last.to_i
            end
          end

          def validate_faraday_response!(faraday_response)
            if error = faraday_response.body[:errors][0]
              fail CypherError, "#{ANSI::CYAN}#{error[:code]}#{ANSI::CLEAR}: #{error[:message]}"
            end

            return if (200..299).include?(status = faraday_response.status)

            fail CypherError, "Expected 200-series response for #{faraday_response.env.url} (got #{status})"
          end
        end
      end
    end
  end
end
