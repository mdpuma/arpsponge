##############################################################################
# @(#)$Id$
##############################################################################
#
# ARP Sponge network packet routines.
#
# Most of the basic decoding was ripped from the original NetPacket::
# modules.
#
# See the LICENSE file that came with this package.
#
# S.Bakker.
#
###############################################################################
package M6::ARP::NetPacket;

use strict;
use Readonly;

BEGIN {
	use Exporter;

	our $VERSION = 1.04;
	our @ISA = qw( Exporter );

    my @functions = qw(
            decode_ethernet decode_ipv4 decode_arp
        );

    my @variables = qw(
            $ETH_TYPE_IP
            $ETH_TYPE_IPv4
            $ETH_TYPE_ARP
            $ETH_TYPE_IPv6
            $ARP_OPCODE_REQUEST
            $ARP_OPCODE_REPLY
            $ARP_HTYPE_ETHERNET
            $ARP_PROTO_IP
            $ARP_PROTO_IPv4
        );

	our @EXPORT_OK = ( @functions, @variables );
	our @EXPORT    = ();

	our %EXPORT_TAGS = ( 
			'all'    => [ @EXPORT_OK ],
			'func'   => [ @functions ],
			'vars'   => [ @variables ],
		);
}

# The only things we're interested in right now...
Readonly our $ETH_TYPE_IP    => 0x0800;
Readonly our $ETH_TYPE_IPv4  => 0x0800;
Readonly our $ETH_TYPE_ARP   => 0x0806;
Readonly our $ETH_TYPE_IPv6  => 0x86dd;

Readonly our $ARP_OPCODE_REQUEST  => 1;
Readonly our $ARP_OPCODE_REPLY    => 2;
Readonly our $ARP_HTYPE_ETHERNET  => 1;
Readonly our $ARP_PROTO_IP        => $ETH_TYPE_IPv4;
Readonly our $ARP_PROTO_IPv4      => $ETH_TYPE_IPv4;

=pod

=head1 NAME

M6::ARP::NetPacket - (partially) decode ethernet, IP and ARP packets

=head1 SYNOPSIS

 use M6::ARP::NetPacket qw( :all );
 use M6::ARP::Util qw( :all );

 $packet = ...;

 $eth_data = decode_ethernet($packet);

 if ( $eth_data->{type} == $ETH_TYPE_IPv4 ) {
    $ip_data = decode_ipv4( $eth_data->{'data'} );

    printf( "%s -> %s, %d bytes (including IP header)\n",
            hex2ip( $ip_data->{'src_ip'} ),
            hex2ip( $ip_data->{'dest_ip'} ),
            $ip_data->{'len'} );
 }

 if ( $eth_data->{type} == $ETH_TYPE_ARP ) {
    $arp_data = decode_arp( $eth_data->{'data'} );
    
    if ($arp_data->{opcode} == $ARP_OPCODE_REQUEST) {
        printf( "ARP WHO-HAS %s TELL %s\@%s\n",
                hex2ip( $arp_data->{'tpa'} ),
                hex2ip( $arp_data->{'spa'} ),
                hex2mac( $arp_data->{'sha'} ) );
    }
    else {
        printf( "ARP %s IS-AT %s\n",
                hex2ip( $arp_data->{'spa'} ),
                hex2ip( $arp_data->{'sha'} ) );
    }
 }

=head1 DESCRIPTION

This module defines a number of routines to decode raw pcap packet data
on Ethernet, IP and ARP level.

The semantics are similar to those of the L<NetPacket>(3) family, except that:

=over

=item 1.

All IP and MAC addresses are decoded as hex strings (as opposed to what e.g.
L<NetPacket::IP>(3) does).

=item 2.

We decode only a minimal subset of a packet, just enough for the
L<arpsponge>(1)'s purposes.

=back

=head1 VARIABLES

The variables below can be imported individually, by using the C<:vars> or C<:all> tags:

  use M6::ARP::NetPacket qw( :vars );
  use M6::ARP::NetPacket qw( :all );

Note that these variables are all read-only.

=over

=item X<$ETH_TYPE_IP>I<$ETH_TYPE_IP>, X<$ETH_TYPE_IPv4>I<$ETH_TYPE_IPv4>

Ethernet C<type> for IPv4 frames.

=item X<$ETH_TYPE_IPv6>I<$ETH_TYPE_IPv6>

Ethernet C<type> for IPv6 frames.

=item X<$ETH_TYPE_ARP>I<$ETH_TYPE_ARP>

Ethernet C<type> for ARP frames.

=item X<$ARP_OPCODE_REQUEST>I<$ARP_OPCODE_REQUEST>

ARP C<opcode> for ARP requests.

=item X<$ARP_OPCODE_REPLY>I<$ARP_OPCODE_REPLY>

ARP C<opcode> for ARP replies.

=item X<$ARP_HTYPE_ETHERNET>I<$ARP_HTYPE_ETHERNET>

ARP C<htype> for Ethernet hardware addresses.

=item X<$ARP_PROTO_IP>I<$ARP_PROTO_IP>, X<$ARP_PROTO_IPv4>I<$ARP_PROTO_IPv4>

ARP C<proto> for IPv4 requests/replies.

=back

=head1 FUNCTIONS

The functions below can be imported individually, by using the C<:func> or C<:all> tags:

  use M6::ARP::NetPacket qw( :all );
  use M6::ARP::NetPacket qw( :func );

All functions return a hash ref (not an object!) with a minimal set of fields
set. They do not set C<_parent> or C<_frame>.

=over

=item X<decode_ethernet>B<decode_ethernet> ( I<DATA> )

(TCP/IP Illustrated, Volume 1, Section 4.4, p56-57. The section is about ARP,
but shows the Ethernet header as well.)

Decode I<DATA> as a raw Ethernet frame. Returns a hash with the following
fields:

=over 12

=item C<src_mac>

Source MAC address as a 12 digit, lowercase hex string.

=item C<dest_mac>

Destination MAC address as a 12 digit, lowercase hex string.

=item C<type>

Integer denoting the Ethernet type field.

=item C<data>

Payload data of the Ethernet frame.

=back

=cut

sub decode_ethernet {
    my $pkt = shift;
    my $self = {};

    if (defined $pkt) {
        # Much faster than the "Nn" + sprintf() trick.
        ($self->{dest_mac}, $self->{src_mac}, $self->{type}, $self->{data})
            = unpack('H12H12na*', $pkt);
    }
    return $self;
}

###############################################################################

=item X<decode_ip>B<decode_ip> ( I<DATA> )

Synonymous with L<decode_ipv4()|/decode_ipv4>.

=cut

sub decode_ip { &decode_ipv4 }

=item X<decode_ipv4>B<decode_ipv4> ( I<DATA> )

(TCP/IP Illustrated, Volume 1, Section 3.2, p34-37.)

Decode I<DATA> as a raw IPv4 packet. Returns a hash with the following
fields:

=over 12

=item C<ver>

IP version (4, duh).

=item C<hlen>

Header length.

=item C<tos>

Type of Service.

=item C<len>

IP packet length.

=item C<id>

IP datagram identification.

=item C<foffset>

Fragment offset.

=item C<ttl>

Time To Live.

=item C<proto>

IP protocol field.

=item C<cksum>

IP checksum.

=item C<src_ip>

Source IP address as an 8 digit, lowercase hex string.

=item C<dest_ip>

Destination IP address as an 8 digit, lowercase hex string.

=item C<options>

IP options field.

=item C<data>

Payload data of the IP datagram.

=back

=cut

sub decode_ipv4 {
    my $pkt = shift;

    return {} if ! defined $pkt;

    my $self = {};

    # Unpack IP addresses directly as "H8".
    (my $tmp, $self->{tos}, $self->{len}, $self->{id}, $self->{foffset},
              $self->{ttl}, $self->{proto}, $self->{cksum},
              $self->{src_ip}, $self->{dest_ip}, $self->{options})
        = unpack('CCnnnCCnH8H8a*', $pkt);

    # Extract bit fields
    $self->{ver} = ($tmp & 0xf0) >> 4;
    $self->{hlen} = $tmp & 0x0f;

    $self->{flags} = $self->{foffset} >> 13;
    $self->{foffset} = ($self->{foffset} & 0x1fff) << 3;

    # Decode variable length header options and remaining data in field

    # Option length is number of 32 bit words
    my $olen = $self->{hlen}*4 - 20;
       $olen = 0 if $olen < 0;  # Check for bad hlen

    ($self->{options}, $self->{data})
        = unpack("a${olen}a*", $self->{options});

    return $self;
}

###############################################################################

=item X<decode_arp>B<decode_arp> ( I<DATA> )

(TCP/IP Illustrated, Volume 1, Section 4.4, p56-57.)

Decode I<DATA> as a raw ARP packet. Returns a hash with the following
fields:

=over 12

=item C<htype>

Hardware type field. This routine is only designed for
I<$ARP_HTYPE_ETHERNET>.

=item C<proto>

Type of protocol address. This routine is only designed for
I<$ARP_PROTO_ETHERNET>.

=item C<hlen>, C<plen>

Hardware address length and protocol address length (in octets). For IPv4
on Ethernet these should be 6 and 4, respectively.

=item C<opcode>

Operation type: one of I<$ARP_OPCODE_REQUEST> or I<$ARP_OPCODE_REPLY>.

=item C<sha>

Source hardware (MAC) address
as a 12 digit, lowercase hex string.

=item C<spa>

Source protocol (IP) address
as an 8 digit, lowercase hex string.

=item C<tha>

Target hardware (MAC) address
as a 12 digit, lowercase hex string.

=item C<tpa>

Target protocol (IP) address
as an 8 digit, lowercase hex string.

=item C<type>

Integer denoting the Ethernet type field.

=item C<data>

Payload data (always C<undef>)

=back

In theory the ARP packet could be for an AppleTalk address over Token Ring, but
in practice (and our use case), we only see IP over Ethernet.

Still, it pays to check the C<proto> and C<htype> fields, just to make sure you
don't get nonsense.

=cut

sub decode_arp {
    my $pkt = shift;
    return {} if !defined $pkt;

    my $self = {};

    #($self->{htype}, $self->{proto}, $self->{hlen}, $self->{plen},
    #    $self->{opcode}, $self->{sha}, $self->{spa}, $self->{tha},
    #    $self->{tpa}) =
    #        unpack('nnCCnH12H8H12H8' , $pkt);

    # Ninetynine out of a hundred times hlen is 6 and plen is 4 (IP over ethernet),
    # but just in case:
    ($self->{htype}, $self->{proto}, $self->{hlen}, $self->{plen},
     $self->{opcode}, my $payload)
            = unpack('nnCCna*' , $pkt);
        
    # Take the long way home.
    my $spec = 'H'.$self->{hlen}.'H'.$self->{plen};
    ($self->{sha}, $self->{spa}, $self->{tha}, $self->{tpa})
            = unpack($spec.$spec, $payload);

    $self->{data} = undef;
    return $self;
}

###############################################################################
1;

__END__

=back

=head1 EXAMPLE

See the L</SYNOPSIS> section.

=head1 SEE ALSO

L<M6::ARP::Sponge(3)|M6::ARP::Sponge>,
L<M6::ARP::Util(3)|M6::ARP::Util>,
L<NetPacket(3)|NetPacket>.

=head1 AUTHORS

Steven Bakker at AMS-IX (steven.bakker@ams-ix.net).

=cut
