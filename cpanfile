# Syntax
requires 'mro';
requires 'indirect';
requires 'multidimensional';
requires 'bareword::filehandles';
requires 'Syntax::Keyword::Try', '>= 0.24';
requires 'Future', '>= 0.47';
requires 'Future::Queue';
requires 'Future::AsyncAwait', '>= 0.50';
requires 'Object::Pad', '>= 0.39';
requires 'Role::Tiny', '>= 2.002004';

# Streams
requires 'Ryu', '>= 3.000';
requires 'Ryu::Async', '>= 0.019';

# IO::Async
requires 'Heap', '>= 0.80';
requires 'IO::Async::Notifier', '>= 0.78';
requires 'IO::Async::SSL', '>= 0.22';

# Functionality
requires 'curry', '>= 1.001';
requires 'Log::Any', '>= 1.709';
requires 'Log::Any::Adapter', '>= 1.709';
requires 'Config::Any', '>= 0.32';
requires 'YAML::XS', '>= 0.83';
requires 'JSON::MaybeUTF8', '>= 2.000';
requires 'Unicode::UTF8';
requires 'Time::Moment', '>= 0.44';
requires 'Sys::Hostname';

#requires 'Module::Load';
#requires 'Module::Runtime';
#requires 'Module::Pluggable::Object';

requires 'Getopt::Long';
requires 'Pod::Usage';
requires 'List::Util', '>= 1.56';
requires 'List::Keywords', '>= 0.06';

# Transport
requires 'Net::Async::Redis', '>= 3.013';
requires 'Net::Async::HTTP', '>= 0.48';
requires 'Net::Async::HTTP::Server', '>= 0.13';
requires 'Database::Async', '>= 0.013';
requires 'Database::Async::Engine::PostgreSQL', '>= 0.010';


# Dzil
requires 'Dist::Zilla';
requires 'ExtUtils::MakeMaker', '6.64';
requires 'Dist::Zilla::Plugin::Prereqs::FromCPANfile';
requires 'Dist::Zilla::Plugin::CheckPrereqsIndexed';
requires 'Dist::Zilla::Plugin::VersionFromModule';
requires 'Dist::Zilla::Plugin::OurPkgVersion';
requires 'Dist::Zilla::Plugin::CopyFilesFromRelease';
