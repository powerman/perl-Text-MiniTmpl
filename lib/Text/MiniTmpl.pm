package Text::MiniTmpl;

use warnings;
use strict;
use Carp;

use version; our $VERSION = qv('1.1.6');    # REMINDER: update Changes

# REMINDER: update dependencies in Makefile.PL
use Perl6::Export::Attrs;
use JSON::XS qw( encode_json );
use URI::Escape qw();
use HTML::Entities qw();

use constant UNSAFE_HTML=> '&"\'<>' . join q{},map{chr}0..8,11,12,14..31,127;
use constant RAWPRE     => q{$}.__PACKAGE__.'::__ .= ';
use constant RAWPOST    => q{};
use constant UTF8PRE    => q{$}.__PACKAGE__.'::__utf8 = ';
use constant UTF8POST   => 'utf8::encode($'.__PACKAGE__.'::__utf8);' .
                           q{$}.__PACKAGE__.'::__ .= $'.__PACKAGE__.'::__utf8;';

our $__;
our $__utf8;
our $TMPL_DIR = q{./};

my %CACHE;
my ($PRE, $POST) = (UTF8PRE, UTF8POST);


sub raw :Export {
    my ($is_raw) = @_;
    ($PRE, $POST) = $is_raw ? (RAWPRE, RAWPOST) : (UTF8PRE, UTF8POST);
    return;
}

sub render :Export {
    my ($tmpl, %p) = @_;
    my $path = $tmpl =~ m{\A[.]?/}xms ? $tmpl : "$TMPL_DIR$tmpl";
    1 while $path =~ s{(\A|/) (?![.][.]?/) [^/]+/[.][.]/}{$1}xms; ## no critic(ProhibitPostfixControls)
    my $pkg = caller;
    $CACHE{$path}{$pkg} ||= tmpl2code($tmpl);
    return ${ $CACHE{$path}{$pkg}->(%p) };
}

sub tmpl2code :Export {
    my ($tmpl) = @_;
    my $path = $tmpl =~ m{\A[.]?/}xms ? $tmpl : "$TMPL_DIR$tmpl";
    1 while $path =~ s{(\A|/) (?![.][.]?/) [^/]+/[.][.]/}{$1}xms; ## no critic(ProhibitPostfixControls)
    my $dir = $path;
    $dir =~ s{/[^/]*\z}{/}xms;
    my $line = 1;
    my $pkg = caller;
    if ($pkg eq __PACKAGE__) {
        $pkg = caller 1;
    }
    my $e
        = 'package '.$pkg.'; use warnings; use strict;'
        . 'sub {'
        . 'local $'.__PACKAGE__.'::__ = q{};'
        . 'local $'.__PACKAGE__."::TMPL_DIR = \"\Q$dir\E\";"
        . 'local %_ = @_;'
        . "\n#line $line \"$path\"\n"
        ;
    open my $fh, '<', $path or croak "open: $!";
    my $s = do { local $/ = undef; <$fh> };
    close $fh or croak "close: $!";
    while ( 1 ) {
        $e .=
            $s=~/\G<!--& ( (?>[^-]*) .*? ) -->/xmsgc
                ? "$1;"
          : $s=~/\G&~    ( (?>[^~]*) .*? ) ~&/xmsgc
                ? "$1;"
          : $s=~/\G@~    ( (?>[^~]*) .*? ) ~@/xmsgc
                ? $PRE."HTML::Entities::encode_entities(''.(do { $1; }), ".__PACKAGE__.'::UNSAFE_HTML);'.$POST
          : $s=~/\G\#~   ( (?>[^~]*) .*? ) ~\#/xmsgc
                ? $PRE."do { $1; };".$POST
          : $s=~/\G\^~   ( (?>[^~]*) .*? ) ~\^/xmsgc
                ? $PRE."URI::Escape::uri_escape_utf8(''.(do { $1; }));".$POST
          : $s=~/\G      ( (?>[^<&@\#^]*) .*? ) (?=<!--&|&~|@~|\#~|\^~|\z)/xmsgc
                ? q{$}.__PACKAGE__."::__ .= \"\Q$1\E\";"
          : last;
        $line += $1 =~ tr/\n//;
        $e .= "\n#line $line \"$path\"\n";
    }
    $e .= '; return \$'.__PACKAGE__.'::__ }';
    # do instead of eval to have better diagnostics and support source filters
    open my $fhe, '<', \$e or croak "open: $!"; ## no critic(RequireBriefOpen)
    local @INC = ( sub {shift @INC; $fhe}, @INC );
    my $code = do '[eval]';
    croak $@ if $@;
    return $code;
}

sub encode_js :Export {
    my ($s) = @_;
    $s = quotemeta $s;
    $s =~ s/\n/n/xmsg;
    while ($s =~ s/\G([^\\]*(?:\\[^.+-][^\\]*)*)\\([.+-])/$1$2/xmsg) {};
    return $s;
}

sub encode_js_data :Export {
    my ($s) = @_;
    if ($POST eq UTF8POST) {
        $s = JSON::XS->new->encode($s);
    } else {
        $s = encode_json($s);
    }
    $s =~ s{</script}{<\\/script}xmsg;
    return $s;
}


1; # Magic true value required at end of module
__END__

=encoding utf8

=head1 NAME

Text::MiniTmpl - Compile and render templates


=head1 SYNOPSIS

    use Text::MiniTmpl qw( render );

    $html1 = render('template.html', %params1);
    $html2 = render('template.html', %params2);


=head1 DESCRIPTION

Compile templates with embedded perl code into anonymous subroutines.
These subroutines can be (optionally) cached, and executed to render these
templates with (optional) parameters.

Perl code in templates will be executed with:

    package PACKAGE_WHERE_render_OR_tmpl2code_WAS_CALLED;
    use warnings;
    use strict;

Recursion in templates is supported (you can call render() or tmpl2code()
inside template to "include" another template inside current one).
Path name to included template can be set in several ways:

=over

=item *

path relative to current template's directory: C< 'file', 'dir/file', '../file' >

=item *

path relative to current working directory (where your script executed):
C< './file', './dir/file' >

=item *

absolute path: C< '/dir/file' >

=back

When you render top-level template (i.e. call render() from your script,
not inside some template) paths C< 'file' > and C< './file' >, C< 'dir/file' >
and C< './dir/file' > are same.

Correctly report compile errors in templates, with template name and line
number.

=head2 Unicode support

Files with templates should be in UTF8. Parameters for templates should be
perl Unicode scalars. Rendered template (returned by render() or by
function returned by tmpl2code()) will be in UTF8.

You can disable it using raw(1) (see below) to get more speed.

=head2 Source Filters support

Probably not all filters will work inside templates - keep in mind filter
will see autogenerated (by tmpl2code()) perl function's code instead of
plain template text. See `perldoc perlfilter` for more details.

Example:

    &~ use Filter::CommaEquals; ~&
    &~ @{ $_{users} } ,= 'GHOST' ~&
    &~ for (@{ $_{users} }) { ~&
    <p>Hello, @~ $_ ~@!</p>
    &~ } ~&

=head2 Template syntax

Any template become perl function after parsing. This function will accept
it parameters in C< %_ > (it start with C< local %_ = @_; >).
Of course, you can use my() and local() variables in template (their scope
will be full template, not only placeholder's block where they was defined).

=over

=item &~ PERL CODE ~&

=item <!--& PERL CODE -->

Execute PERL CODE but don't output anything.

=item @~ PERL CODE ~@

Execute PERL CODE and output it result (last calculated expression)
escaped using HTML::Entities::encode_entities().

=item ^~ PERL CODE ~^

Execute PERL CODE and output it result (last calculated expression)
escaped using URI::Escape::uri_escape_utf8().

=item #~ PERL CODE ~#

Execute PERL CODE and output it result (last calculated expression)
AS IS, without any escaping.

=item any other text ...

... will be output AS IS


=back

Example templates:

    To: #~ $_{email} ~#
    Hello, #~ $username ~#. Here is items your asked for:
    &~ for (@{ $_{items} }) { ~&
        #~ $_ ~#
    &~ } ~&

    ---cut header.html---
    <html>
    <head><title>@~ $_{pagetitle} ~@</title></head>
    <body>

    ---cut index.html---
    #~ render('header.html', pagetitle=>'Home') ~#
    <p>Hello, @~ $_{username} ~@.</p>
    &~ # In HTML you may prefer <!--& instead of &~ for code blocks ~&
    <!--& for (@{ $_{topics} }) { -->
    <a href="news.cgi?topic=^~ $_ ~^&user=^~ $_{user} ~^">
        News about @~ $_ ~@
    </a>
    <!--& } -->
    #~ render('footer.html') ~#

    ---cut footer.html---
    </body>
    </html>


=head1 EXPORTS

Nothing by default, but all documented functions can be explicitly imported.


=head1 INTERFACE 

=over

=item render( $filename, %params )

Render template from $filename with %params.

This is caching wrapper around tmpl2code(), which avoid calling
tmpl2code() second time for same $filename.

Example:

    $html = render( 'template/index.html',
        title   => $title,
        name    => $name,
    );

Return STRING with rendered template.


=item tmpl2code( $filename )

Read template from $filename (may be absolute or relative to current
template's directory or current working directory - see L</DESCRIPTION>),
compile it into ANON function.

This function can be executed with C< ( %params ) > parameters,
it will render $filename template with given C< %params > and return
SCALARREF to rendered text.

Example:

    $code = tmpl2code( 'template/index.html' );
    $html = ${ $code->( title=>$title, name=>$name ) };

Return CODEREF to that function.


=item raw( $is_raw )

If $is_raw TRUE disable Unicode support.
To enable Unicode again call raw() with $is_raw FALSE.

B<Disabling Unicode support will speedup this module in about 1.5 times!>

When Unicode support disabled your parameters used to render template will
be used in template AS IS, without attempt to encode them to UTF8.
This mean you shouldn't use perl Unicode scalars in these parameters anymore.

This affect only templates processed by tmpl2code() after calling raw()
(beware caching effect of render()).


=item encode_js( $scalar )

Encode $scalar (string or number) for inserting into JavaScript code
(usually inside HTML templates).

Example:

    <script>
    var int_from_perl =  #~ encode_js($number) ~#;
    var str_from_perl = '#~ encode_js($string) ~#';
    </script>

Return encoded string.


=item encode_js_data( $complex )

Encode $complex data structure (HASHREF, ARRAYREF, etc. - any data type
supported by JSON::XS) for inserting into JavaScript code (usually inside
HTML templates).

Example:

    <script>
    var hash_from_perl  = #~ encode_js_data( \%hash ) ~#;
    var array_from_perl = #~ encode_js_data( \@array ) ~#;
    </script>

Return encoded string.


=back


=head1 SPEED AND SIZE

This module implemented under 100 lines (about 3KB) of pure Perl code.
And while code is terse enough, I believe it still simple and clean.

While this is pure-perl module with many enough features, it's still very
fast - you can do your own benchmarking using cool L<Template::Benchmark>
module, here is results from my system:

=over

=item instance_reuse

This test simulate standard FastCGI which read template from HDD and
compile it only once (when this template requested first time), and for
next requests it just render it using cached anon subroutine.

            Rate   XS?
    TT        29/s  -  Template::Toolkit (2.22)
    TT_X      95/s  Y  Template::Toolkit (2.22) with Stash::XS
    HM       704/s  -  HTML::Mason (1.45)
    TeCS     738/s  Y  Text::ClearSilver (0.10.5.4)
    TeMT    1131/s  -  Text::MicroTemplate (0.18)
    TeMMHM  1173/s  -  Text::MicroMason (2.12) using Text::MicroMason::HTMLMason
  * TMTU    1357/s  -  Text::MiniTmpl (1.1.0) with enabled Unicode
    MoTe    1629/s  -  Mojo::Template ()
  * TMT     2054/s  -  Text::MiniTmpl (1.1.0)
    TeClev  5966/s  Y  Text::Clevery (0.0004) in XS mode
    TeXs    6761/s  Y  Text::Xslate (0.2015)

=item uncached_disk

This test simulate standard CGI which read template from HDD, compile and
render it on each run - no caches used at all (except HDD files caching by OS).

            Rate   XS?
    TeXs     1.4/s  Y  Text::Xslate (0.2015)
    TeClev   1.5/s  Y  Text::Clevery (0.0004) in XS mode
    HM      12.6/s  -  HTML::Mason (1.45)
    MoTe    21.0/s  -  Mojo::Template ()
    TeMT    32.1/s  -  Text::MicroTemplate (0.18)
    TeMMHM  36.2/s  -  Text::MicroMason (2.12) using Text::MicroMason::HTMLMason
  * TMTU    54.1/s  -  Text::MiniTmpl (1.1.0) with enabled Unicode
  * TMT     67.9/s  -  Text::MiniTmpl (1.1.0)
    TeTmpl   448/s  Y  Text::Tmpl (0.33)
    TeCS     725/s  Y  Text::ClearSilver (0.10.5.4)
    HTP     1422/s  Y  HTML::Template::Pro (0.9504)


=back


=head1 BUGS AND LIMITATIONS

No bugs have been reported.


=head1 SUPPORT

Please report any bugs or feature requests through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Text-MiniTmpl>.
I will be notified, and then you'll automatically be notified of progress
on your bug as I make changes.

You can also look for information at:

=over

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Text-MiniTmpl>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Text-MiniTmpl>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Text-MiniTmpl>

=item * Search CPAN

L<http://search.cpan.org/dist/Text-MiniTmpl/>

=back


=head1 AUTHOR

Alex Efros  C<< <powerman-asdf@ya.ru> >>


=head1 LICENSE AND COPYRIGHT

Copyright 2007-2010,2014 Alex Efros <powerman-asdf@ya.ru>.

This program is distributed under the MIT (X11) License:
L<http://www.opensource.org/licenses/mit-license.php>

Permission is hereby granted, free of charge, to any person
obtaining a copy of this software and associated documentation
files (the "Software"), to deal in the Software without
restriction, including without limitation the rights to use,
copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following
conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.

