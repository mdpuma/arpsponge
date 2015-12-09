#===============================================================================
#
#       Module:  M6::CLI
#
#  Description:  parse/validate/completion for programs that use ReadLine.
#
#       Author:  Steven Bakker (SB), <steven.bakker@ams-ix.net>
#      Created:  2011-04-21 13:28:04 CEST (as M6::ReadLine)
#
#   Copyright (c) 2011-2015 AMS-IX B.V.; All rights reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself. See perldoc
#   perlartistic.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
#   See the "Copying" file that came with this package.
#
#===============================================================================

package M6::CLI;

use parent qw( Exporter );

use Modern::Perl;
use Moo;

use Params::Check qw( check );
use POSIX ( );

use Term::ReadLine;
use Term::ReadKey;
use NetAddr::IP;
use Data::Dumper;
use Scalar::Util qw( reftype );
use FindBin;
 
has IN              => ( is => 'rw', writer => '_IN'  );
has OUT             => ( is => 'rw', writer => '_OUT' );
has term            => ( is => 'rw' );
has history_file    => ( is => 'rw' );
has ip_network      => ( is => 'rw' );
has syntax          => ( is => 'rw' );
has pager           => ( is => 'rw' );
has error           => ( is => 'rw', writer => '_error' );
has prompt          => ( is => 'rw', writer => '_TERM' );

BEGIN {
    our $VERSION     = '1.00';
	my @check_func  = qw(
        check_ip_address_arg
        complete_ip_address_arg
        check_int_arg
        check_float_arg
        check_bool_arg
        match_prefix
    );
	my @gen_functions = qw(
        compile_syntax
        init_readline exit_readline
        parse_line
        print_error_cond print_error
        last_error set_error clear_error
        yesno print_output
        clr_to_eol term_width fmt_text
    );
	my @functions   = (@check_func, @gen_functions);
    my @vars        = qw(
        $TERM $IN $OUT $PROMPT $PAGER
        $HISTORY_FILE $IP_NETWORK
    );

	our @EXPORT_OK   = (@functions, @vars);
	our @EXPORT      = @gen_functions;

	our %EXPORT_TAGS = (
        func  => \@functions,
        check => \@check_func,
        all   => \@EXPORT_OK,
        vars  => \@vars
    );
}

our $TERM         = undef;
our $IN           = \*STDIN;
our $OUT          = \*STDOUT;
our $PROMPT       = '';
our $HISTORY_FILE = '';
our $IP_NETWORK   = NetAddr::IP->new('0/0');
our $SYNTAX       = {};
our $PAGER        = join(' ', qw(
                        less --no-lessopen --no-init
                             --dumb  --quit-at-eof
                             --quit-if-one-screen
                    ));

my $ERROR         = undef;

our %TYPES = (
        'int' => {
            'verify'   => \&check_int_arg,
            'complete' => [],
        },
        'float' => {
            'verify'   => \&check_float_arg,
            'complete' => [],
        },
        'bool' => {
            'verify'   => \&check_bool_arg,
            'complete' => [ qw( true false on off yes no ) ],
        },
        'mac-address' => {
            'verify'   => \&check_mac_address_arg,
            'complete' => [],
        },
        'ip-address' => {
            'verify'   => \&check_ip_address_arg,
            'complete' => \&complete_ip_address_arg,
        },
        'string' => {
            'verify'   => sub { return clear_error($_[1]) },
            'complete' => []
        },
        'filename' => {
            'verify'   => sub { return clear_error($_[1]) },
            'complete' => \&complete_filename,
        },
    );


#
# $word = match_unique_prefix($input, \@words [, $silent_err]);
#
sub match_unique_prefix {
    my $input = lc shift;
    my ($words, $silent_err) = @_;

    my $word;
    for my $w (sort @$words) {
        if (substr(lc $w, 0, length($input)) eq $input) {
            if (defined $word) {
                return print_error_cond(!$silent_err,
                        qq{"$input" is ambiguous: matches "$word" and "$w"}
                    );
            }
            $word = $w;
        }
    }
    return clear_error($word);
}


sub _is_valid_num {
    my $func = shift;
    my $arg  = shift;
    my $err_s;
    my %opts = (err => \$err_s, min => undef, max => undef, inclusive => 1, @_);

    if (!defined $arg || length($arg) == 0) {
        ${$opts{err}} = 'not a valid number';
        return;
    }

    my ($num, $unparsed) = $func->($arg);
    if ($unparsed) {
        ${$opts{err}} = 'not a valid number';
        return;
    }

    if ($opts{inclusive}) {
        if (defined $opts{min} && $num < $opts{min}) {
            ${$opts{err}} = 'number too small';
            return;
        }
        if (defined $opts{max} && $num > $opts{max}) {
            ${$opts{err}} = 'number too large';
            return;
        }
    }
    else {
        if (defined $opts{min} && $num <= $opts{min}) {
            ${$opts{err}} = 'number too small';
            return;
        }
        if (defined $opts{max} && $num >= $opts{max}) {
            ${$opts{err}} = 'number too large';
            return;
        }
    }
    ${$opts{err}} = '';
    return $num;
}


sub is_valid_int   { return _is_valid_num(\&POSIX::strtol, @_) }
sub is_valid_float { return _is_valid_num(\&POSIX::strtod, @_) }

sub is_valid_ip {
    my $arg = shift;
    my $err_s;
    my %opts = (err => \$err_s, network => undef, @_);

    if (!defined $arg || length($arg) == 0) {
        ${$opts{err}} = q/"" is not a valid IPv4 address/;
        return;
    }

    my $ip = NetAddr::IP->new($arg);
    if (!$ip) {
        ${$opts{err}} = qq/"$arg" is not a valid IPv4 address/;
        return;
    }
    
    return $ip->addr() if !$opts{network};
   
    if (my $net = NetAddr::IP->new($opts{-network})) {
        return $ip->addr() if $net->contains($ip);
        ${$opts{err}} = qq/$arg is out of range /.$net->cidr();
        return;
    }
    else {
        ${$opts{err}} = qq/** INTERNAL ** is_valid_ip(): -network /
                       . qq/argument "$opts{network}" is not valid/;
        warn ${$opts{err}};
        return;
    }
}


# $byte = check_int_arg(\%spec, $arg, 'byte');
sub check_int_arg {
    my ($spec, $arg, $silent) = @_;
    my $argname = $spec->{name} // 'num';

    my $err;
    my $val = is_valid_int($arg, %$spec, err=>\$err);
    if (defined $val) {
        return clear_error($val);
    }
    return print_error_cond(!$silent, qq{$argname: "$arg": $err});
}

# $percentage = check_float_arg({min=>0, max=>100}, $arg, 'percentage');
sub check_float_arg {
    my ($spec, $arg, $silent) = @_;
    my $argname = $spec->{name} // 'num';

    my $err;
    my $val = is_valid_float($arg, %$spec, err=>\$err);
    if (defined $val) {
        return clear_error($val);
    }
    return print_error_cond(!$silent, qq{$argname: "$arg": $err});
}

# $bool = check_bool_arg($min, $max, $arg, 'dummy');
sub check_bool_arg {
    my ($spec, $arg, $silent) = @_;

    my $argname = $spec->{name} // 'bool';

    if ($arg =~ /^(1|yes|true|on)$/i) {
        return clear_error(1);
    }
    elsif ($arg =~ /^(0|no|false|off)$/i) {
        return clear_error(0);
    }
    return print_error_cond(!$silent,
                qq{$argname: "$arg" is not a valid boolean});
}

sub check_ip_address_arg {
    my ($spec, $arg, $silent) = @_;

    my $argname = $spec->{name} // 'ip';

    my $err;
    $arg = is_valid_ip($arg, network=>$IP_NETWORK->cidr, err=>\$err);
    if (defined $arg) {
        return clear_error($arg);
    }
    return print_error_cond(!$silent, qq{$argname: $err});
}

sub check_mac_address_arg {
    my ($spec, $arg, $silent) = @_;

    my $argname = $spec->{name} // 'mac';

    if ($arg =~ /^(?:[\da-f]{1,2}[:.-]){5}[\da-f]{1,2}$/i
        || $arg =~ /^(?:[\da-f]{1,4}[:.-]){2}[\da-f]{1,4}$/i
        || $arg =~ /^[\da-f]{1,12}$/i) {
        return clear_error($arg);
    }
    else {
        print_error_cond($silent, qq{$argname: "$arg" is not a valid MAC address});
        return;
    }
}

sub complete_ip_address_arg {
    my $partial = shift;

    my $network   = $IP_NETWORK->short;
    
    my $fixed_octets = int($IP_NETWORK->masklen / 8);

    return $network if $fixed_octets == 4;
    return undef    if $fixed_octets == 0;

    my $fixed = join('.', (split(/\./, $network))[0..$fixed_octets-1] );
    my $have_len = length($partial);
    if ($have_len > 0 && $have_len > length($fixed)) {
        my @completions = (map { "$fixed.$_" } (0..255));
        if ($have_len >= $fixed_octets) {
            # Turn IP addresses into "91.200.17.1[x[x[x]]]"
            # That is, keep the part that has already matched
            # and reveal only the next digit, turn the rest into "x".
            my %completions = map {
                    my $keep = substr($_, 0, $have_len+1);
                    my $hide = length($_) > $have_len+1 
                                ? substr($_, $have_len+1)
                                : '';
                    $hide =~ s/[\da-f]/x/gi;
                    $keep.$hide => 1;
                } @completions;
            return keys %completions;
            #return grep { length($_) <= $have_len+1 } @completions;
        }
        else {
            return grep { length($_) == length($fixed)+2 } @completions;
        }
    }
    else {
        return ("$fixed.", "$fixed.x");
    }
}

sub complete_filename {
    my $partial = shift;
    my $attribs = $TERM->Attribs;
    my @list;
    my $state = 0;
    while (my $f = $attribs->{filename_completion_function}->($partial, $state)) {
        push @list, $f;
        $state = 1;
    }
    return @list;
}

# $ok = parse_line($line, \@parsed, \%args);
#
#   Parse the input line in $line against $SYNTAX (compiled syntax). All
#   parsed, literal command words (i.e. neither argument nor option) are
#   stored in @parsed. All arguments and options are stored in %args.
#
#   Returns 1 on success, undef on failure.
#
sub parse_line {
    my ($line, $parsed, $args) = @_;
    chomp($line);
    my @words = split(' ', $line);
    $args->{'-options'} = [];
    return parse_words(\@words, { words => $SYNTAX }, $parsed, $args);
}

# $ok = parse_words(\@words, $syntax, \@parsed, \%args);
#
#   Parse the words in @words against $syntax (compiled syntax). All
#   parsed, literal command words (i.e. neither argument nor option) are
#   stored in @parsed. All arguments and options are stored in %args.
#
#   Returns 1 on success, undef on failure.
#
sub parse_words {
    my $words      = shift;
    my $syntax     = shift;
    my $parsed     = shift;
    my $args       = shift;

    # Command line options (--something, -s), are stored
    # in the '-options' array in %$args. They'll be parsed
    # later on.
    while (@$words && $$words[0] =~ /^-{1,2}./) {
        push @{$args->{-options}}, shift @$words;
    }

    if (my $word_list = $syntax->{words}) {
        my $words_str = join(q{ }, sort grep { length $_ } keys %$word_list);

        if (!@$words) {
            if (exists $word_list->{''}) {
                return 1;
            }
            else {
                return print_error("@$parsed: expected one of:\n",
                                   fmt_text($words_str, indent => 4));
                #return print_error("@$parsed: expected one of:\n$words_str");
            }
        }
        my $w = $words->[0];
        my $l = length($w);
        my @match = grep { substr($_,0, $l) eq $w } keys %$word_list;
        if (@match == 1) {
            push @$parsed, $match[0];
            shift @$words;
            return parse_words($words, $word_list->{$match[0]},
                               $parsed, $args);
        }
        elsif (@match > 1) {
            return print_error(
                        qq{ambibuous input "$$words[0]"; matches:\n},
                        fmt_text(join(' ', sort @match), indent => 4),
                    );
        }
        else {
            return print_error(
                        qq{invalid input "$$words[0]"; expected one of:\n},
                        fmt_text($words_str, indent => 4)
                    );
        }
    }
    elsif (my $arg_spec = $syntax->{arg}) {
        my $arg_name = $arg_spec->{name};
        $args->{$arg_name} = $arg_spec->{default};
        if (!@$words) {
            if ($arg_spec->{optional}) {
                return parse_words($words, $arg_spec, $parsed, $args);
            }
            else {
                return print_error("@$parsed: missing <$arg_name> argument");
            }
        }
        my $arg_val;
        if (my $type = $TYPES{$arg_spec->{type}}) {
            my $validate = $type->{verify} // sub { $_[0] };
            eval { $arg_val = $validate->($arg_spec, $words->[0]) };
            if (!defined $arg_val && $@) { 
                return print_error(
                    qq{@$parsed: internal error on parsing '$$words[0]': $@}
                );
            }
        }
        else {
            $arg_val = $words->[0];
        }
        return if ! defined $arg_val;
        $args->{$arg_name} = $arg_val;
        shift @$words;
        return parse_words($words, $arg_spec, $parsed, $args);
    }
    elsif (@$words) {
        return print_error(
                qq{@$parsed: expected end of line instead of "$$words[0]"\n}
               );
    }
    return 1;
}

# @completions = complete_words(\@words, $partial, \%syntax);
#
#   @words   - Words leading up to $partial.
#   $partial - Word to complete.
#   %syntax  - Syntax definition tree.
#
# Recursively traverse the %syntax try by looking up consecutive values of
# @words. At the end, either the current element's "words" entry will give
# the list of completions, or the "completion" function of the "var" entry.
#
sub complete_words {
    my $words      = shift;
    my $partial    = shift;
    my $syntax     = shift;

    if (my $word_list = $syntax->{words}) {
        my @next = sort grep { length $_ } keys %$word_list;
        my @literals = @next;
        if (exists $word_list->{''}) {
            push @literals, '';
            push @next, '(return)';
        }
        if (!@$words) {
            return (\@literals, \@next);
        }
        my $w = $words->[0];
        my $l = length($w);
        my @match = grep { substr($_,0, $l) eq $w } keys %$word_list;
        if (@match == 1) {
            shift @$words;
            return complete_words($words, $partial, $word_list->{$match[0]});
        }
        elsif (@match > 1) {
            return ([],
                    [qq{** "$$words[0]" ambiguous; matches: }
                    . join(', ', sort @match)]
                );
        }
        else {
            return([],
                   [qq{** "$$words[0]" invalid; expected: }
                   . join(", ", sort @next)]
                );
        }
    }
    elsif (my $arg_spec = $syntax->{arg}) {
        my $arg_name = $arg_spec->{name};
        my @next = ("<$arg_name>");
        my @literal = ();
        if ($arg_spec->{optional}) {
            push @next, "(return)";
        }
        if (@$words == 0) {
            if ($arg_spec->{complete}) {
                if (reftype $arg_spec->{complete} eq 'CODE') {
                    push @literal, $arg_spec->{complete}->($partial);
                }
                else {
                    push @literal, @{$arg_spec->{complete}};
                }
            }
            return (\@literal, \@next);
        }

        my $validate = $arg_spec->{verify} // sub { $_[0] };
        my $arg_val;
        eval { $arg_val = $validate->($arg_spec, $words->[0], 1) };
        if (defined $arg_val) {
            shift @$words;
            return complete_words($words, $partial, $arg_spec);
        }
        else {
            return([],
                ['** error'.(defined last_error() ? ': '.last_error() : '')]
            );
        }
    }
    elsif (@$words || length($partial)) {
        return([], [
                '** error: trailing junk "'.join(' ', @$words, $partial).'"'
            ]);
    }
    else {
        return([], ['(return)']);
    }
}


# @completions = complete_line($text, $line, $start);
#
#   $text  - (Partial) word to complete.
#   $line  - Input line so far.
#   $start - Position where the $text starts in $line.
#
sub complete_line {
    my ($text, $line, $start) = @_;

    chomp($line);
    my $words   = substr($line, 0, $start);
    #print "<$words> <$text>\n";
    my @words = split(' ', $words);
    my ($literal, $description) 
            = complete_words(\@words, $text, { words=>$SYNTAX });
    if (!@$literal && @$description) {
        print "\n";
        print map { "\t$_" } @$description;
        print "\n";
        $TERM->on_new_line();
    }
    return @$literal;
}

# $cols = term_width()
sub term_width {
    my $term = @_ ? shift : $TERM;
    my ($rows, $cols) = $term ? $term->get_screen_size() : (25, 80);
    return $cols;
}

# $clrt_to_eol = clr_to_eol();
sub clr_to_eol {
    state $CLR_TO_EOL = readpipe('tput el 2>/dev/null');
    return $CLR_TO_EOL;
}


# $fmt = fmt_text( [text =>] $text, [ opt => val, ... ]);
sub fmt_text {
    my $text;

    if (@_ % 2 == 1) { 
        $text = shift;
    }

    my $opts = check({
            prefix => { store => \(my $prefix = '') },
            maxlen => { store => \(my $maxlen = term_width()-4) },
            indent => { store => \(my $indent = 0) },
            text   => { store => \$text },
        }, {@_}, 1);

    if ($prefix !~ /\n$/) {
        # The prefix does not end in a newline.
        my ($prefix_tail) = $prefix =~ /^(.*)\z/m;
        if (length($prefix_tail) < $indent) {
            # The prefix is shorter than the indent, so pad
            # it with spaces until it has the correct length.
            $prefix .= ' ' x ($indent - length($prefix_tail));
        }
    }

    my $indent_text = ' ' x $indent;
    my @words = split(' ', $text);

    my $out = $prefix;
    my $pos_in_line;
    if ($out =~ /^(.+?)\z/m) {
        $pos_in_line = length($1);
    }
    else {
        $out .= $indent_text;
        $pos_in_line = $indent;
    }

    # Push words onto $out, making sure each line doesn't run over
    # $maxlen.
    for my $w (@words) {
        if ($pos_in_line + length($w) + 1 > $maxlen) {
            # Next word would make the line run over $maxlen,
            # so insert a newline.
            $out .= "\n$indent_text";
            $pos_in_line = $indent;
        }
        if ($out =~ /\S+$/) {
            # Always eparate words with a space.
            $out .= ' ';
            $pos_in_line++;
        }
        $out .= $w;
        $pos_in_line += length($w);
    }
    $out .= "\n";
    return $out;
}


sub exit_readline {
    return if !$TERM;

    if (defined $HISTORY_FILE) {
        if (! $TERM->WriteHistory($HISTORY_FILE)) {
            print_error("** WARNING: cannot save history to $HISTORY_FILE");
        }
    }
}

sub init_readline {
    my %args = (
            'history_lines' => 1000,
            'completion'    => \&complete_line,
            'name'          => $FindBin::Script,
            @_,
    );
    $args{history_file} //= "$::ENV{HOME}/.$args{name}_history";
    $args{prompt}       //= "$args{name}> ";

    $TERM = Term::ReadLine->new( $args{name}, *STDIN, *STDOUT );

    $HISTORY_FILE = $args{history_file};
    if (-f $args{history_file}) {
        if (! $TERM->ReadHistory($HISTORY_FILE)) {
            print_error("** WARNING: cannot read history",
                        " from $HISTORY_FILE\n");
        }
    }

    my $attribs = $TERM->Attribs;
        #$attribs->{attempted_completion_function} = \&rl_completion;
        $attribs->{completion_function} = $args{completion};

    $TERM->set_key('?', 'possible-completions'); # Behave as a Brocade :-)
    #$term->clear_signals();
    $TERM->StifleHistory($args{history_lines});

    $IN  = $TERM->IN  || \*STDIN;
    $OUT = $TERM->OUT || \*STDOUT;

    select $OUT;
    $| = 1;

    $PROMPT = $args{prompt};
    $::SIG{INT} = 'IGNORE';

    return ($TERM, $PROMPT, $IN, $OUT);
}

# $compiled = compile_syntax(\%src);
#
#   Compile a convenient syntax description to a parse tree. The $compiled
#   tree can be used by parse_line().
#
sub compile_syntax {
    my $src = shift;
    my $curr = { words => {} };
    while (my ($key, $spec) = each %$src) {
        _compile_syntax_element($curr, $spec, split(' ', $key)) or return;
    }
    $SYNTAX = $curr->{words};
    return $SYNTAX;
}


# $compiled = _compile_syntax_element($curr, $spec, $word, @rest);
#
#   We've parsed the syntax element of $spec up to $word. Extend
#   the tree at $curr with all the branches of $word.
#
sub _compile_syntax_element {
    my ($curr, $spec, $word, @rest) = @_;

    if ($word) {
        for my $branch (split(qr{\|}, $word)) {
            if (!_compile_branch($curr, $spec, $branch, @rest)) {
                return;
            }
        }
    }
    return $curr;
}


# $compiled = _compile_branch($curr, $spec, $word, @rest);
#
#   We've parsed the syntax element of $spec up to $word. $word
#   is one of the branches at this point. Extend the tree at $curr
#   with $word and whatever follows.
#
sub _compile_branch {
    my ($curr, $spec, $word, @rest) = @_;

    if (substr($word,0,1) ne '$') {
        # We have a literal.
        my $w = $curr->{words} = $curr->{words} // {};
        $curr = $w->{$word} = $w->{$word} // {};
    }
    else {
        # We have a variable.
        my $optional = $word =~ s/^(.*)\?$/$1/;
        my $varname = substr($word,1);
        $curr->{arg} //= {};
        my $a = $curr->{arg};
        %$a = ( %$a, %{$spec->{$word}} );
        $a->{name}     = $varname;
        $a->{optional} = $optional;
        if ($a->{type}) {
            if (my $tspec = $TYPES{$a->{type}}) {
                %$a = (%$tspec, %$a);
            }
            else {
                return print_error("$$a{type}: unknown type\n");
            }
        }
        $curr = $a;
    }
    return _compile_syntax_element($curr, $spec, @rest);
}

# ===========================================================================
# ERROR HANDLING
# ===========================================================================

# print_error_cond($bool, $msg, ...);
#
#   Always returns false, prints to STDERR if $bool is true,
#   always ends with a newline.
#
sub print_error_cond {
    my $cond = shift;
    my $out = join('', @_);

    chomp($out);

    if ($cond) {
        say STDERR $out;
        $TERM && $TERM->on_new_line();
    }
    return set_error($out);
}


# print_error($msg, ...);
#
#   Always returns false, always prints to STDERR, always ends
#   with a newline.
#
sub print_error {
    return print_error_cond(1, @_);
}

# set_error($msg, ...);
#
#   Always returns false, set "last" error message.
#
sub set_error {
    $ERROR = join('', @_);
    chomp($ERROR);
    return;
}

# clear_error();
#
#   Always returns true, clear "last" error.
#
sub clear_error {
    $ERROR = undef;
    return @_ == 1 ? $_[0] : @_;
}

# last_error($msg, ...);
#
#   Returns "last" error message.
#
sub last_error {
    return $ERROR;
}

# print_output($msg, ...);
#
#   Print output, through $PAGER if interactive.
#
sub print_output {
    my $out = join('', @_);
       $out .= "\n" if $out !~ /\n\Z/ && length($out);

    my $ret = 1;
    my $curr_fh = select;
    if ($TERM && -t $curr_fh) {
        local($::SIG{PIPE}) = 'IGNORE';
        open my $pager, "|$PAGER";
        $pager->print($out);
        close $pager;
        $ret = $? == 0;
        $TERM->on_new_line();
    }
    else {
        $ret = print $out;
    }
    return $ret;
}

# $answer = yesno($question, "Ynq");
sub yesno {
    my ($question, $answers) = @_;
    my ($default) = $answers =~ /([A-Z])/;
    $default = 'N' if !defined $default;
    ReadMode 4;
    print "$question ($answers)? $default\b";
    my $answer = undef;
    my $key = '?';
    while (defined ($key = ReadKey(0))) {
        foreach ($key) {
            if ($_ eq "\c[")  { $key = 'n' }
            elsif (/[\r\n ]/) { $key = $default }
        }
        foreach (lc $key) {
            if (index(lc $answers, $_) >= 0) {
                if    ($_ eq "y") { $answer = +1  }
                elsif ($_ eq "n") { $answer =  0  }
                elsif ($_ eq "q") { $answer = -1 }
            }
        }
        last if defined $answer;
    }
    ReadMode 0;
    print "$key\n";
    return $answer;
}

1;

__END__

=pod

=head1 NAME

M6::CLI - AMS-IX extensions on top of Term::ReadLine

=head1 SYNOPSIS

 use FindBin;
 use M6::CLI qw( :all );

 my $prog = $FindBin::Script;
 init_readline(
            'history_lines' => 1000,
            'completion'    => \&M6::CLI::complete_line,
            'name'          => $prog,
            'history_file'  => "$::ENV{HOME}/.${prog}_history",
        );

 my $syntax = compile_syntax({
    'quit' => { '?' => 'Exit program.' },
    'help' => { '?' => 'Show command summary.' },
    'ping $count? $delay?' => {
        '?'      => 'Send "ping" packets, display RTT.',
        '$count' => { type=>'int', min=>1, default=>1 },
        '$delay' => { type=>'float', min=>0.01, default=>1 },
    }
 });

 while (1) {
    my $input = $TERM->readline('~> ');
    last if !defined $input;

    next if $input =~ /^\s*(?:#.*)?$/;

    if (parse_line($input, \(my @parsed), \(my %args))) {
        print "@parsed\n";
    }
 }

 ...

 exit_readline();

=head1 DESCRIPTION

AMS-IX extensions on top of Term::ReadLine.

=head1 VARIABLES

=over

=item I<$TERM>

=item I<$IN>

=item I<$OUT>

=item I<$PROMPT>

=item I<$PAGER>

=item I<$HISTORY_FILE>

=item I<$IP_NETWORK>

=back

=head1 FUNCTIONS

=head2 Initialisation / Clean-up

=over

=item B<compile_syntax>
X<compile_syntax>

=item B<exit_readline>
X<exit_readline>

=item B<init_readline>
X<init_readline>

=back

=head2 Validation

=over

=item B<check_bool_arg>
X<check_bool_arg>

=item B<check_float_arg>
X<check_float_arg>

=item B<check_int_arg>
X<check_int_arg>

=item B<check_ip_address_arg>
X<check_ip_address_arg>

=item B<check_mac_address_arg>
X<check_mac_address_arg>

=item B<match_unique_prefix>
X<match_unique_prefix>

=item B<parse_line>
X<parse_line>

=item B<parse_words>
X<parse_words>

=item B<is_valid_int>
X<is_valid_int>

=item B<is_valid_float>
X<is_valid_float>

=item B<is_valid_ip>
X<is_valid_ip>

=back

=head2 Completion

=over

=item B<complete_ip_address_arg>
X<complete_ip_address_arg>

=item B<complete_line>
X<complete_line>

=item B<complete_words>
X<complete_words>

=back

=head2 Output / Error Handling

=over

=item B<fmt_text> ( I<text>, [ I<param> =E<gt> I<val>, ... ] )
X<fmt_text>

=item B<fmt_text> ( B<text> =E<gt> I<text>, [ I<param> =E<gt> I<val>, ... ] )

Parameters: 

=over

=item B<prefix> =E<gt> I<string>

=item B<maxlen> =E<gt> I<int>

=item B<indent> =E<gt> I<int>

=back

Format I<text>, so that it wraps at B<maxlen> columns
(default is terminal width minus 4), with the first line
prefixed with B<prefix> and the body indented by B<indent>
spaces.

For non-empty prefixes, there is always a space between
the prefix and the I<text>.

The return value is the reflowed string, which is always
terminated by a newline.

Example:

   fmt_text( ""
    -prefix => 'MONKEY, n.',
    -text   => 'An arboreal animal which makes itself'
              .' at home in genealogical trees.'
    -maxlen => 4,
    -indent => 10,
   );

Result:

    |0--------1---------2---------3|
    |1--------0---------0---------0|
    |MONKEY, n. An arboreal animal |
    |    which makes itself at home|
    |    in genealogical trees.    |

Note that the lines in the resulting string are not guaranteed
to stay within the B<maxlen> limit: if a single word exceeds
the length limit, it is added on a (possibly indented) line on
its own.

Example:

   fmt_text( ""
    -prefix => 'MONKEY, n.',
    -text   => 'An-arboreal-animal-which-makes itself'
              .' at home in genealogical trees.'
    -maxlen => 4,
    -indent => 10,
   );

Result:

    |0--------1---------2---------3|
    |1--------0---------0---------0|
    |MONKEY, n.                    |
    |   An-arboreal-animal-which-makes
    |   itself at home in          |
    |   genealogical trees.        |

=item B<clear_error>
X<clear_error>

=item B<last_error>
X<last_error>

=item B<print_error>
X<print_error>

=item B<print_error_cond>
X<print_error_cond>

=item B<print_output>
X<print_output>

=item B<set_error>
X<set_error>

=item B<clr_to_eol>
X<clr_to_eol>

Return the string that will clear the current line on the terminal from the cursor
position onwards, i.e. return the terminal's C<el> string.

=back

=head2 Miscellaneous

=over

=item B<yesno> ( I<question>, I<answer> )
X<yesno>

Ask I<question> and read a yes/no answer.

The I<answers> string should contain a combination of the letters C<y>,
C<n>, and C<q>, corresponding to resp. C<yes>, C<no>, C<quit>. If any
of the letters is capitalised, it is taken to be the default answer
if the user hits Enter or Space (if none given, the default is C<N>).

The return value is an integer:

=over

=item C<+1>

Yes.

=item C<0>

No.

=item C<-1>

Quit.

=back

=back

=head1 SEE ALSO

L<less>(1),
L<Term::ReadKey>(3pm),
L<Term::ReadLine>(3pm),
L<Term::ReadLine::Gnu>(3pm).

=head1 AUTHOR

Steven Bakker E<lt>steven.bakker@ams-ix.netE<gt>, AMS-IX B.V.; 2011-2015.

=head1 COPYRIGHT

Copyright 2011-2015, AMS-IX B.V.
Distributed under GPL and the Artistic License 2.0.

=cut
