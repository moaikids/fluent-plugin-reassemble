require 'time'
require 'uri'
require 'tzinfo'

module Fluent
    class ReassembleOutput < Fluent::Output
        Fluent::Plugin.register_output('reassemble', self)
        config_param :output_tag, :string, :default => nil
        config_param :assemble, :string, :default => nil
        config_param :null_to_null, :bool, :default => false
        config_param :null_to_empty, :bool, :default => false
        config_param :datetime_format, :string, :default => '%Y/%m/%d %H:%M:%S'
        config_param :date_format, :string, :default => '%Y/%m/%d'
        config_param :time_format, :string, :default => '%H:%M:%S'
        config_param :tz, :string, :default => nil

        def configure(conf)
            super
            unless config.has_key?('output_tag')
                raise Fluent::ConfigError, "you must set 'output_tag'"
            end
            unless config.has_key?('assemble')
                raise Fluent::ConfigError, "you must set 'assemble'"
            end
            if config.has_key?('tz')
                ENV["TZ"] = config['tz']
            end
            #assemble definition format
            # {extract_key1}:{replaced_key1}:{operation1},{extract_key2}:{replaced_key2}:{operation2},....{extract_keyN}:{replaced_keyN}:{operationN}
            @reassemble_conf = []
            @assemble.split(",").each{ |conf|
                extract, replace, operation = conf.split(":")
                if extract.nil? || extract.empty?
                    next
                else
                    extract = extract.strip
                end
                if replace.nil? || replace.empty?
                    replace = extract
                else
                    replace = replace.strip
                end
                unless operation.nil? || operation.empty?
                    operation = operation.strip
                end
                @reassemble_conf.push({:extract => extract, :replace => replace, :operation => operation})
            }
            $log.info "reassemble conf : " + @reassemble_conf.to_s
        end

        def emit(tag, es, chain)
            es.each {|time,record|
                json = {}
                @reassemble_conf.each { |conf| 
                    extract_key = conf[:extract]
                    replaced_key = conf[:replace]
                    operation = conf[:operation]
                    val = convert(traverse(record, extract_key), operation)
                    if val
                        json[replaced_key] = val
                    elsif @null_to_null
                        json[replaced_key] = nil
                    elsif @null_to_empty
                        json[replaced_key] = ""
                    end
                }
                Fluent::Engine.emit(@output_tag, time, json)
            }
        end 

        def traverse(data, key)
            val = data
            key.split('.').each{ |k|
                if val.is_a?(Hash) && val.has_key?(k)
                    val = val[k]
                else
                    return nil
                end
            }
            return val
        end

        def convert(val, operation)
            unless val
                return val
            end
            unless operation
                return val
            end
         
            begin
                case operation.downcase
                when "to_s"
                    return val.to_s
                when "to_i"
                    return val.to_i
                when "to_f"
                    return val.to_f
                when "unixtime_to_datetime"
                    return Time.at(val.to_i).strftime(@datetime_format)
                when "unixtime_to_date"
                    return Time.at(val.to_i).strftime(@date_format)
                when "unixtime_to_time"
                    return Time.at(val.to_i).strftime(@time_format)
                when "url_to_host","url_to_domain"
                    return URI(val.to_s).host
                when "url_to_path"
                    return URI(val.to_s).path
                else
                    return val
                end
            rescue
                $log.warn $!
                return val
            end

        end
    end
end
