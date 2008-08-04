package Spread::Client::Connection::Sync;
use strict;
use warnings;
use bytes;

use base qw/Spread::Client::Connection/;

sub new {
    my $class = shift;

    my $self = {};

    $self->{sock} = $class->create_new_socket( @_ );

    return bless $self, $class;
}

sub is_async { return 0 }

sub sock {
    my $self = shift;

    return $self->{sock};
}

sub read {
    my $self = shift;

    my $buffer;
    my $sock = $self->{sock};
    my ($ret, $total, $len) = (0, 0, $_[0]);

    do {
        $ret = sysread( $sock, $buffer, $len, $ret);

        # TODO handle return exceptions like undef
        $total += $ret;
        $len = $_[0] - $total;
    } while( $len > 0 and !$_[1]);

    return \$buffer;
}

sub write {
    my $self = shift;

    my $sock = $self->{sock};

    # TODO handle return exceptions
    return syswrite( $sock, ${$_[0]}, length ${$_[0]} );
}

sub private_group {
    my $self = shift;

    if( $_[0] ) {
        $self->{private_group} = $_[0];
    }

    return $self->{private_group};
}

sub close {
    my $self = shift;
    my $sock = $self->{sock};

    close $sock;
}

1;
