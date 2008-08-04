use strict;
use warnings;
use Test::More tests => 8;

BEGIN { use_ok('Spread::Client') }
use Spread::Client::Constant ':all';

SKIP: {

    skip 'SPREAD_NAME environment variable not defined', 7 unless $ENV{SPREAD_NAME};

    my $spread_name = $ENV{SPREAD_NAME} || '4803@localhost';
    
    my $private_name = 'mrperl' . int(rand(99));
    my $group_name = 'test_group' . int(rand(99));
    my $orig_message = 'this is a message';
    
    # Connect
    my $conn;
    eval {
        $conn = Spread::Client::connect(
                spread_name   => $spread_name,
                private_name  => $private_name,
            );
    };
    ok(!$@, 'connect succesful');
    diag('Exception: ' . $@)
        if $@;
    
    # If needed
    my $private_group = $conn->private_group;
    
    Spread::Client::join( conn   => $conn,
                        groups => [ $group_name ],
                        );
    
    Spread::Client::multicast( conn    => $conn,
                            type => SAFE_MESS,
                            groups  => [ $group_name ],
                            message => $orig_message,
                            );
    
    for (1..2) {
    
        my ($service_type, $sender, $groups, $mess_type, $endian, $message) =
        Spread::Client::receive( conn  => $conn );
        
        if( $_ == 1 ) {
            is($sender, $group_name, 'Group name matches this is good.');
            ok( ref $message eq 'HASH', 'We got back a join message, this is good.');
            is($groups->[0], $conn->private_group, 'Groups came back correctly, this is good.');
            is($message->{members}->[0], $conn->private_group, 'Shows we joined correctly, this is good.');
        }
        else {
            is($sender, $conn->private_group, 'Sender matches this is good.');
            is($message, $orig_message, 'Message matches this is good.');
        } 
    }
    
    Spread::Client::leave( conn   => $conn,
                        groups => [ $group_name ],
                        );
    
    Spread::Client::disconnect( conn => $conn );
}
