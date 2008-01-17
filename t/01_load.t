use Test::More tests => 3;
use_ok( 'POE::Component::Server::SimpleHTTP::Connection' );
use_ok( 'POE::Component::Server::SimpleHTTP::Response' );
use_ok( 'POE::Component::Server::SimpleHTTP' );
diag( "Testing POE::Component::Server::SimpleHTTP-$POE::Component::Server::SimpleHTTP::VERSION, POE-$POE::VERSION, Perl $], $^X" );
