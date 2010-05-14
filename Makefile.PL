#use ExtUtils::MakeMaker;
use inc::Module::Install;

$ENV{PERL_MM_USE_DEFAULT}=1 if $Module::Install::AUTHOR;

name 'POE-Component-Server-SimpleHTTP';
author 'Apocalypse <APOCAL@cpan.org>';
license 'perl';
auto_license holder => 'Apocalypse, Chris Williams, Eriam Schaffter, Marlon Bailey and Philip Gwyn';
perl_version '5.006';
version_from 'lib/POE/Component/Server/SimpleHTTP.pm';
abstract_from 'lib/POE/Component/Server/SimpleHTTP.pm';

# Build the prerequisite list
requires    'HTTP::Date'       =>    0;
requires    'Carp'             =>    0;
requires    'Sys::Hostname'    =>    0;
requires    'POE'              =>    '1.0000';
requires    'Storable'         =>    0;
requires    'Socket'           =>    0;
requires    'HTTP::Request'    =>    0;
requires    'HTTP::Response'   =>    0;
requires    'Moose'	       =>    0.81;
requires    'MooseX::AttributeHelpers' => 0;
requires    'MooseX::POE'      =>    0.205;

build_requires   'Test::More'                   => 0.47;
build_requires	 'POE::Filter::HTTP::Parser'	=> 0.02;
build_requires	 'Test::POE::Client::TCP'	=> 0.10;

my $value = prompt( 'Do you want to test streaming ( requires POE::Component::Client::HTTP ) [y/N]?', 'N' );
build_requires   'POE::Component::Client::HTTP' => 0.82 if $value =~ /^Y$/i;

# Ask users if they want SSL support
$value = prompt( 'Do you want SSL support ( requires POE::Component::SSLify ) [y/N]?', 'N' );

# Add to the prereqs PoCo::SSLify?
requires 'POE::Component::SSLify' => '0.04' if $value =~ /^Y$/i;

# Thanks to Matt Trout for this tip
makemaker_args(dist => { PREOP => "$^X tools/git-log.pl > ./Changes" });

auto_provides;
githubmeta;

WriteAll();
