##############################################################################
# @(#)$Id$
##############################################################################
#
# ARP Stuff Utility routines
#
# (c) Copyright AMS-IX B.V. 2004-2005;
#
# See the LICENSE file that came with this package.
#
# S.Bakker.
#
###############################################################################
package M6::ARP::Util;

BEGIN {
	use Exporter;

	our $VERSION = 1.02;
	our @ISA = qw( Exporter );

	our @EXPORT_OK = qw( int2ip ip2int hex2ip ip2hex hex2mac mac2hex mac2mac );
	our @EXPORT    = ();

	our %EXPORT_TAGS = ( 
			'all'    => [ @EXPORT_OK ]
		);

}

=pod

=head1 NAME

M6::ARP::Util - IP/MAC utility routines

=head1 SYNOPSIS

 use M6::ARP::Util qw( :all );

 $ip  = int2ip( $num );
 $num = ip2int( $ip  );
 $ip  = hex2ip( $hex  );
 $hex = ip2hex( $ip );
 $mac = hex2mac( $hex );
 $hex = mac2hex( $mac );
 $mac = mac2mac( $mac );

=head1 DESCRIPTION

This module defines a number of routines to convert IP and MAC
representations to and from various formats.

=head1 FUNCTIONS

=over

=cut

###############################################################################

=item X<int2ip>B<int2ip> ( I<num> )

Convert a (long) integer to a dotted decimal IP address. Return the
dotted decimal string.

Example: int2ip(3250751620) returns "193.194.136.132".

=cut

sub int2ip {
	hex2ip(sprintf("%08x", shift @_));
};

###############################################################################

=item X<ip2int>B<ip2int> ( I<IPSTRING> )

Dotted decimal IPv4 address to integer representation.

Example: ip2int("193.194.136.132") returns "3250751620".

=cut

sub ip2int {
	hex(ip2hex(shift @_));
};

###############################################################################

=item X<hex2ip>B<hex2ip> ( I<HEXSTRING> )

Hexadecimal IPv4 address to dotted decimal representation.

Example: hex2ip("c1c28884") returns "193.194.136.132".

=cut

sub hex2ip {
	my $hex = shift;

	$hex =~ /(..)(..)(..)(..)/;
	my $ip = sprintf("%d.%d.%d.%d", hex($1), hex($2), hex($3), hex($4));
	return $ip;
};

###############################################################################

=item X<ip2hex>B<ip2hex> ( I<IPSTRING> )

Dotted decimal IPv4 address to hex representation.

Example: ip2hex("193.194.136.132")
returns "c1c28884".

=cut

sub ip2hex {
	return sprintf("%02x%02x%02x%02x", split(/\./, shift));
};

###############################################################################

=item X<hex2mac>B<hex2mac> ( I<HEXSTRING> )

Hexadecimal MAC address to colon-separated hex representation.

Example: hex2mac("a1b20304e5f6")
returns "a1:b2:03:04:e5:f6"

=cut

sub hex2mac {
	my $hex = substr("000000000000".(shift @_), -12);
	$hex =~ /(..)(..)(..)(..)(..)(..)/;
	return sprintf("%02x:%02x:%02x:%02x:%02x:%02x",
			hex($1), hex($2), hex($3), hex($4), hex($5), hex($6));
};

###############################################################################

=item X<mac2hex>B<mac2hex> ( I<macstring> )

Any MAC address to hex representation.

Example:
mac2hex("a1:b2:3:4:e5:f6")
returns "a1b20304e5f6".

=cut

sub mac2hex {
	my @mac = split(/[\s\.\-:\-]/, shift);
	return undef if 12 % int(@mac);
	my $digits = int(12 / int(@mac));
	my $hex;
	my $pref = "0" x $digits;
	foreach (@mac) { $hex .= substr($pref.$_, -$digits) }
	return lc $hex;
};

###############################################################################

=item X<mac2mac>B<mac2mac> ( I<MACSTRING> )

Any MAC address to colon-separated hex representation (6 groups of 2 digits).

Example: mac2mac("a1b2.304.e5f6")
returns "a1:b2:03:04:e5:f6"

=cut

sub mac2mac {
	hex2mac(mac2hex($_[0]));
}

1;

__END__

=back

=head1 EXAMPLE

See the L</SYNOPSIS> section.

=head1 SEE ALSO

L<perl(1)|perl>, L<M6::ARP::Sponge(3)|M6::ARP::Sponge>.

=head1 AUTHORS

Steven Bakker at AMS-IX (steven.bakker@ams-ix.net).

=cut
