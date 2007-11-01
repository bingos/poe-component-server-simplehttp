#use ExtUtils::MakeMaker;
use inc::Module::Install;

name 'POE-Component-Server-SimpleHTTP';
author 'Apocalypse <APOCAL@cpan.org>';
license 'perl';
version_from 'lib/POE/Component/Server/SimpleHTTP.pm';
abstract_from 'lib/POE/Component/Server/SimpleHTTP.pm';

# Build the prerequisite list
requires    'HTTP::Date'       =>    0;
requires    'Carp'             =>    0;
requires    'Sys::Hostname'    =>    0;
requires    'POE'              =>    '0.38';
requires    'Storable'         =>    0;
requires    'Socket'           =>    0;
requires    'HTTP::Request'    =>    0;
requires    'HTTP::Response'   =>    0;

build_requires   'Test::More'                   => 0.47;
build_requires   'LWP::UserAgent'               =>    0;
build_requires   'POE::Component::Client::HTTP' =>    0;

# Ask users if they want SSL support
my $value = prompt( 'Do you want SSL support ( requires POE::Component::SSLify ) [Y/n]?', 'N' );

# Add to the prereqs PoCo::SSLify?
if ( $value =~ /^Y$/i ) {
    requires 'POE::Component::SSLify' => '0.04';
}

# Ask users if they want PreFork support
$value = prompt( 'Do you want PreFork support ( requires IPC::Shareable ) [Y/n]?', 'N' );

# Add to the prereqs IPC::Shareable?
if ( $value =~ /^Y$/i ) {
    requires 'IPC::Shareable' => '0';
}
WriteAll();
