use inc::Module::Install;

name     'Text-MiniTmpl';
all_from 'lib/Text/MiniTmpl.pm';

die "Windows not supported\n" if $^O =~ /Win/;

requires        'version';
requires        'Perl6::Export::Attrs';
requires        'JSON::XS';
requires        'URI::Escape';
requires        'HTML::Entities';

test_requires   'Test::More';
test_requires   'Test::Exception';
test_requires   'Test::MockModule';
test_requires   'Cwd';
test_requires   'Filter::CommaEquals';

recommends      'Test::CheckManifest'   => '0.9';
recommends      'Test::Perl::Critic';
recommends      'Test::Pod::Coverage'   => '1.08';
recommends      'Pod::Coverage'         => '0.18';
recommends      'Test::Pod'             => '1.22';

auto_install;

WriteAll;

