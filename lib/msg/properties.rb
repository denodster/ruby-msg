
class Msg
	#
	# = Introduction
	#
	# A big compononent of +Msg+ files is the property store, which holds
	# all the key/value pairs of properties. The message itself, and all
	# its <tt>Attachment</tt>s and <tt>Recipient</tt>s have an instance of
	# this class.
	#
	# = Storage model
	#
	# Property keys (tags?) can be either simple hex numbers, in the
	# range 0x0000 - 0xffff, or they can be named properties. In fact,
	# properties in the range 0x0000 to 0x7fff are supposed to be the non-
	# named properties, and can be considered to be in the +PS_MAPI+
	# namespace. (correct?)
	# 
	# Named properties are serialized in the 0x8000 to 0xffff range,
	# and are referenced as a guid and long/string pair.
	#
	# There are key ranges, which can be used to imply things generally
	# about keys.
	#
	# Further, we can give symbolic names to most keys, coming from
	# constants in various places. Eg:
	# 
	#   0x0037 => subject
	#   {00062002-0000-0000-C000-000000000046}/0x8218 => response_status
	#   # displayed as categories in outlook
	#   {00020329-0000-0000-C000-000000000046}/"Keywords" => categories
	# 
	# Futher, there are completely different names, coming from other
	# object models that get mapped to these things (CDO's model,
	# Outlook's model etc). Eg "urn:schemas:httpmail:subject"
	# I think these can be ignored though, as they aren't defined clearly
	# in terms of mapi properties, and i'm really just trying to make
	# a mapi property store. (It should also be relatively easy to
	# support them later.)
	# 
	# = Usage
	#
	# The api is driven by a desire to have the simple stuff "just work", ie
	#
	#   properties.subject
	#   properties.display_name
	# 
	# There also needs to be a way to look up properties more specifically:
	# 
	#   properties[0x0037] # => gets the subject
	#   properties[0x0037, PS_MAPI] # => still gets the subject
	#   properties['Keywords', PS_PUBLIC_STRINGS] # => gets outlook's categories array
	# 
	# The abbreviated versions work by "resolving" the symbols to full keys:
	#
	#		# the guid here is just PS_PUBLIC_STRINGS
	#   properties.resolve :keywords # => #<Key {00020329-0000-0000-c000-000000000046}/"Keywords">
	#   # the result here is actually also a key
	#   k = properties.resolve :subject  # => 0x0037
	#   # it has a guid
	#   k.guid == Msg::Properties::PS_MAPI # => true
	#
	# = Parsing
	#
	# There are three objects that need to be parsed to load a +Msg+ property store:
	# 
	# 1. The +nameid+ directory (<tt>Properties.parse_nameid</tt>)
	# 2. The many +substg+ objects, whose names should match <tt>Properties::SUBSTG_RX</tt>
	#    (<tt>Properties#parse_substg</tt>)
	# 3. The +properties+ file (<tt>Properties#parse_properties</tt>)
	#
	# Understanding of the formats is by no means perfect.
	#
	# = TODO
	#
	# * Test cases.
	# * While the key objects are sufficient, the value objects are just plain
	#   ruby types. It currently isn't possible to write to the values, or to know
	#   which encoding the value had.
	# * Consider other MAPI property stores, such as tnef/pst. Similar model?
	#   Generalise this one?
	# * Have added IO support to Ole::Storage. now need to fix Properties. can't use
	#   current greedy-loading approach. still want strings to work nicely:
	#     props.subject
	#   but don't want to be loading up large binary blobs, typically attachments, eg
	#     props.attach_data
	#   probably the easiest solution is that the binary "encoding", be to return an io
	#   object instead. and you must read it if you want it as a string
	#   maybe i can avoid the greedy model anyway? rather than parsing the properties completely,
	#   have it be load based? you request subject, that translates into, please load the right
	#   substg, et voila. maybe redo @raw as a lazy loading hash for substg objects, but do the
	#   others straight away. maybe just parse keys so i know what i've got??
	class Properties
		# duplicated here for now
		SUPPORT_DIR = File.dirname(__FILE__) + '/../..'

		# note that binary and default both use obj.open. not the block form. this means we should
		# #close it later, which we don't. as we're only reading though, it shouldn't matter right?
		# not really good though FIXME
		ENCODINGS = {
			0x000d =>   proc { |obj| obj }, # seems to be used when its going to be a directory instead of a file. eg nested ole. 3701 usually. in which case we shouldn't get here right?
			0x001f =>   proc { |obj| Ole::Types::FROM_UTF16.iconv obj.read }, # unicode
			# ascii
			# FIXME hack did a[0..-2] before, seems right sometimes, but for some others it chopped the text. chomp
			0x001e =>   proc { |obj| obj.read.chomp 0.chr },
			0x0102 =>   proc { |obj| obj.open }, # binary?
			:default => proc { |obj| obj.open }
		}

		SUBSTG_RX = /__substg1\.0_([0-9A-F]{4})([0-9A-F]{4})(?:-([0-9A-F]{8}))?/

		# the property set guid constants
		# these guids are all defined with the macro DEFINE_OLEGUID in mapiguid.h.
		# see http://doc.ddart.net/msdn/header/include/mapiguid.h.html
		oleguid = proc do |prefix|
			Ole::Types::Clsid.parse "{#{prefix}-0000-0000-c000-000000000046}"
		end

		NAMES = {
			oleguid['00020328'] => 'PS_MAPI',
			oleguid['00020329'] => 'PS_PUBLIC_STRINGS',
			oleguid['00020380'] => 'PS_ROUTING_EMAIL_ADDRESSES',
			oleguid['00020381'] => 'PS_ROUTING_ADDRTYPE',
			oleguid['00020382'] => 'PS_ROUTING_DISPLAY_NAME',
			oleguid['00020383'] => 'PS_ROUTING_ENTRYID',
			oleguid['00020384'] => 'PS_ROUTING_SEARCH_KEY',
			# string properties in this namespace automatically get added to the internet headers
			oleguid['00020386'] => 'PS_INTERNET_HEADERS',
			# theres are bunch of outlook ones i think
			# http://blogs.msdn.com/stephen_griffin/archive/2006/05/10/outlook-2007-beta-documentation-notification-based-indexing-support.aspx
			# IPM.Appointment
			oleguid['00062002'] => 'PSETID_Appointment',
			# IPM.Task
			oleguid['00062003'] => 'PSETID_Task',
			# used for IPM.Contact
			oleguid['00062004'] => 'PSETID_Address',
			oleguid['00062008'] => 'PSETID_Common',
			# didn't find a source for this name. it is for IPM.StickyNote
			oleguid['0006200e'] => 'PSETID_Note',
			# for IPM.Activity. also called the journal?
			oleguid['0006200a'] => 'PSETID_Log',
		}

		module Constants
			NAMES.each { |guid, name| const_set name, guid }
		end

		include Constants

		# access the underlying raw property hash
		attr_reader :raw
		# unused (non-property) objects after parsing an +Dirent+.
		attr_reader :unused
		attr_reader :nameid

		# +nameid+ is to provide a way to inherit from parent (needed for property sets for
		# attachments and recipients, which inherit from the msg itself. what about nested
		# msg??)
		def initialize
			@raw = {}
			@unused = []
			@nameid = nil
			# FIXME
			@body_rtf = @body_html = @body = false
		end

		#--
		# The parsing methods
		#++

		def self.load obj, ignore=nil
			prop = Properties.new
			prop.load obj
			prop
		end

		# Parse properties from the +Dirent+ obj
		def load obj
			# we need to do the nameid first, as it provides the map for later user defined properties
			children = obj.children.dup
			if nameid_obj = children.find { |child| child.name == '__nameid_version1.0' }
				children.delete nameid_obj
				@nameid = Properties.parse_nameid nameid_obj
				# hack to make it available to all msg files from the same ole storage object
				class << obj.ole
					attr_accessor :msg_nameid
				end
				obj.ole.msg_nameid = @nameid
			elsif obj.ole
				@nameid = obj.ole.msg_nameid rescue nil
			end
			# now parse the actual properties. i think dirs that match the substg should be decoded
			# as properties to. 0x000d is just another encoding, the dir encoding. it should match
			# whether the object is file / dir. currently only example is embedded msgs anyway
			children.each do |child|
				if child.file?
					begin
						case child.name
						when /__properties_version1\.0/
							parse_properties child
						when SUBSTG_RX
							parse_substg *($~[1..-1].map { |num| num.hex rescue nil } + [child])
						else raise "bad name for mapi property #{child.name.inspect}"
						end
					#rescue
					#	Log.warn $!
					#	@unused << child
					end
				else @unused << child
				end
			end
		end

		# Read nameid from the +Dirent+ obj, which is used for mapping of named properties keys to
		# proxy keys in the 0x8000 - 0xffff range.
		# Returns a hash of integer -> Key.
		def self.parse_nameid obj
			remaining = obj.children.dup
			guids_obj, props_obj, names_obj =
				%w[__substg1.0_00020102 __substg1.0_00030102 __substg1.0_00040102].map do |name|
					remaining.delete obj/name
				end

			# parse guids
			# this is the guids for named properities (other than builtin ones)
			# i think PS_PUBLIC_STRINGS, and PS_MAPI are builtin.
			guids = [PS_PUBLIC_STRINGS] + guids_obj.read.scan(/.{16}/m).map do |str|
				Ole::Types.load_guid str
			end

			# parse names.
			# the string ids for named properties
			# they are no longer parsed, as they're referred to by offset not
			# index. they are simply sequentially packed, as a long, giving
			# the string length, then padding to 4 byte multiple, and repeat.
			names_data = names_obj.read

			# parse actual props.
			# not sure about any of this stuff really.
			# should flip a few bits in the real msg, to get a better understanding of how this works.
			props = props_obj.read.scan(/.{8}/m).map do |str|
				flags, offset = str[4..-1].unpack 'v2'
				# the property will be serialised as this pseudo property, mapping it to this named property
				pseudo_prop = 0x8000 + offset
				named = flags & 1 == 1
				prop = if named
					str_off = *str.unpack('V')
					len = *names_data[str_off, 4].unpack('V')
					Ole::Types::FROM_UTF16.iconv names_data[str_off + 4, len]
				else
					a, b = str.unpack('v2')
					Log.debug "b not 0" if b != 0
					a
				end
				# a bit sus
				guid_off = flags >> 1
				# missing a few builtin PS_*
				Log.debug "guid off < 2 (#{guid_off})" if guid_off < 2
				guid = guids[guid_off - 2]
				[pseudo_prop, Key.new(prop, guid)]
			end

			Log.warn "* ignoring #{remaining.length} objects in nameid" unless remaining.empty?
			# this leaves a bunch of other unknown chunks of data with completely unknown meaning.
			# pp [:unknown, child.name, child.data.unpack('H*')[0].scan(/.{16}/m)]
			Hash[*props.flatten]
		end

		# Parse an +Dirent+, as per <tt>msgconvert.pl</tt>. This is how larger properties, such
		# as strings, binary blobs, and other ole sub-directories (eg nested Msg) are stored.
		def parse_substg key, encoding, offset, obj
			if (encoding & 0x1000) != 0
				if !offset
					# there is typically one with no offset first, whose data is a series of numbers
					# equal to the lengths of all the sub parts. gives an implied array size i suppose.
					# maybe you can initialize the array at this time. the sizes are the same as all the
					# ole object sizes anyway, its to pre-allocate i suppose.
					#p obj.data.unpack('V*')
					# ignore this one
					return
				else
					# remove multivalue flag for individual pieces
					encoding &= ~0x1000
				end
			else
				Log.warn "offset specified for non-multivalue encoding #{obj.name}" if offset
				offset = nil
			end
			# offset is for multivalue encodings.
			unless encoder = ENCODINGS[encoding]
				Log.warn "unknown encoding #{encoding}"
				#encoder = proc { |obj| obj.io } #.read }. maybe not a good idea
				encoder = ENCODINGS[:default]
			end
			add_property key, encoder[obj], offset
		end

		# For parsing the +properties+ file. Smaller properties are serialized in one chunk,
		# such as longs, bools, times etc. The parsing has problems.
		def parse_properties obj
			data = obj.read
			# don't really understand this that well...
			pad = data.length % 16
			unless (pad == 0 || pad == 8) and data[0...pad] == "\000" * pad
				Log.warn "padding was not as expected #{pad} (#{data.length}) -> #{data[0...pad].inspect}"
			end
			data[pad..-1].scan(/.{16}/m).each do |data|
				property, encoding = ('%08x' % data.unpack('V')).scan /.{4}/
				key = property.hex
				# doesn't make any sense to me. probably because its a serialization of some internal
				# outlook structure...
				next if property == '0000'
				case encoding
				when '0102', '001e', '001f', '101e', '101f', '000d'
					# ignore on purpose. not sure what its for
					# multivalue versions ignored also
				when '0003' # long
					# don't know what all the other data is for
					add_property key, *data[8, 4].unpack('V')
				when '000b' # boolean
					# again, heaps more data than needed. and its not always 0 or 1.
					# they are in fact quite big numbers. this is wrong.
#					p [property, data[4..-1].unpack('H*')[0]]
					add_property key, data[8, 4].unpack('V')[0] != 0
				when '0040' # systime
					# seems to work:
					add_property key, Ole::Types.load_time(data[8..-1])
				else
					Log.warn "ignoring data in __properties section, encoding: #{encoding}"
					Log << data.unpack('H*').inspect + "\n"
				end
			end
		end

		def add_property key, value, pos=nil
			# map keys in the named property range through nameid
			if Integer === key and key >= 0x8000
				if !@nameid
					Log.warn "no nameid section yet named properties used"
					key = Key.new key
				elsif real_key = @nameid[key]
					key = real_key
				else
					# i think i hit these when i have a named property, in the PS_MAPI
					# guid
					Log.warn "property in named range not in nameid #{key.inspect}"
					key = Key.new key
				end
			else
				key = Key.new key
			end
			if pos
				@raw[key] ||= []
				Log.warn "duplicate property" unless Array === @raw[key]
				# ^ this is actually a trickier problem. the issue is more that they must all be of
				# the same type.
				@raw[key][pos] = value
			else
				# take the last.
				Log.warn "duplicate property #{key.inspect}" if @raw[key]
				@raw[key] = value
			end
		end

		# resolve an arg (could be key, code, string, or symbol), and possible guid to a key
		def resolve arg, guid=nil
			if guid;        Key.new arg, guid
			else
				case arg
				when Key;     arg
				when Integer; Key.new arg
				else          sym_to_key[arg.to_sym]
				end
			end or raise "unable to resolve key from #{[arg, guid].inspect}"
		end

		# just so i can get an easy unique list of missing ones
		@@quiet_property = {}

		def sym_to_key
			# create a map for converting symbols to keys. cache it
			unless @sym_to_key
				@sym_to_key = {}
				@raw.each do |key, value|
					sym = key.to_sym
					# used to use @@quiet_property to only ignore once
					Log.info "couldn't find symbolic name for key #{key.inspect}" unless Symbol === sym
					if @sym_to_key[sym]
						Log.warn "duplicate key #{key.inspect}"
						# we give preference to PS_MAPI keys
						@sym_to_key[sym] = key if key.guid == PS_MAPI
					else
						# just assign
						@sym_to_key[sym] = key
					end
				end
			end
			@sym_to_key
		end

		# accessors

		def [] arg, guid=nil
			@raw[resolve(arg, guid)] rescue nil
		end

		#--
		# for completeness, but its a mute point until i can write to the ole
		# objects.
		#def []= arg, guid=nil, value
		#	@raw[resolve(arg, guid)] = value
		#end
		#++

		def method_missing name, *args
			if name.to_s !~ /\=$/ and args.empty?
				self[name]
			elsif name.to_s =~ /(.*)\=$/ and args.length == 1
				self[$1] = args[0]
			else
				super
			end
		end

		def to_h
			hash = {}
			sym_to_key.each { |sym, key| hash[sym] = self[key] if Symbol === sym }
			hash
		end

		def inspect
			'#<Properties ' + to_h.map do |k, v|
				v = v.inspect
				"#{k}=#{v.length > 32 ? v[0..29] + '..."' : v}"
			end.join(' ') + '>'
		end

		# -----
		
		# temporary pseudo tags
		
		# for providing rtf to plain text conversion. later, html to text too.
		def body
			return @body if @body != false
			@body = (self[:body] rescue nil)
			@body = (::RTF::Converter.rtf2text body_rtf rescue nil) if !@body or @body.strip.empty?
			@body
		end

		# for providing rtf decompression
		def body_rtf
			return @body_rtf if @body_rtf != false
			@body_rtf = (RTF.rtfdecompr rtf_compressed.read rescue nil)
		end

		# for providing rtf to html conversion
		def body_html
			return @body_html if @body_html != false
			@body_html = (self[:body_html].read rescue nil)
			@body_html = (Msg::RTF.rtf2html body_rtf rescue nil) if !@body_html or @body_html.strip.empty?
			# last resort
			if !@body_html or @body_html.strip.empty?
				Log.warn 'creating html body from rtf'
				@body_html = (::RTF::Converter.rtf2text body_rtf, :html rescue nil)
			end
			@body_html
		end

		# +Properties+ are accessed by <tt>Key</tt>s, which are coerced to this class.
		# Includes a bunch of methods (hash, ==, eql?) to allow it to work as a key in
		# a +Hash+.
		#
		# Also contains the code that maps keys to symbolic names.
		class Key
			include Constants

			attr_reader :code, :guid
			def initialize code, guid=PS_MAPI
				@code, @guid = code, guid
			end

			def to_sym
				# hmmm, for some stuff, like, eg, the message class specific range, sym-ification
				# of the key depends on knowing our message class. i don't want to store anything else
				# here though, so if that kind of thing is needed, it can be passed to this function.
				# worry about that when some examples arise.
				case code
				when Integer
					if guid == PS_MAPI # and < 0x8000 ?
						# the hash should be updated now that i've changed the process
						MAPITAGS['%04x' % code].first[/_(.*)/, 1].downcase.to_sym rescue code
					else
						# handle other guids here, like mapping names to outlook properties, based on the
						# outlook object model.
						NAMED_MAP[self].to_sym rescue code
					end
				when String
					# return something like
					# note that named properties don't go through the map at the moment. so #categories
					# doesn't work yet
					code.downcase.to_sym
				end
			end
			
			def to_s
				to_sym.to_s
			end

			# FIXME implement these
			def transmittable?
				# etc, can go here too
			end

			# this stuff is to allow it to be a useful key
			def hash
				[code, guid].hash
			end

			def == other
				hash == other.hash
			end

			alias eql? :==

			def inspect
				# maybe the way to do this, would be to be able to register guids
				# in a global lookup, which are used by Clsid#inspect itself, to
				# provide symbolic names...
				guid_str = NAMES[guid] || "{#{guid.format}}"
				if Integer === code
					hex = '0x%04x' % code
					if guid == PS_MAPI
						# just display as plain hex number
						hex
					else
						"#<Key #{guid_str}/#{hex}>"
					end
				else
					# display full guid and code
					"#<Key #{guid_str}/#{code.inspect}>"
				end
			end
		end

		#--
		# YUCK moved here because we need Key
		#++

		# data files that provide for the code to symbolic name mapping
		# guids in named_map are really constant references to the above
		MAPITAGS = open("#{SUPPORT_DIR}/data/mapitags.yaml") { |file| YAML.load file }
		NAMED_MAP = Hash[*open("#{SUPPORT_DIR}/data/named_map.yaml") { |file| YAML.load file }.map do |key, value|
			[Key.new(key[0], const_get(key[1])), value]
		end.flatten]
	end
end

