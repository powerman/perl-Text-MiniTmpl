package Text::MiniTmpl;

use warnings;
use strict;
use Carp;

use version; our $VERSION = qv('1.0.0');    # REMINDER: update Changes

# REMINDER: update dependencies in Makefile.PL
use Perl6::Export::Attrs;
use JSON::XS qw( encode_json );
use URI::Escape qw();
use HTML::Entities qw();

use constant UNSAFE_HTML => '&"\'<>' . join q{},map{chr}0..8,11,12,14..31,127;


our $__;
our $TMPL_DIR = q{./};

my %CACHE;


# force newline after every bit of perl code and restore previous line number;
# needed in this case:   <!--& #comment -->@~code()~@
# _restoreline(1, "filename.pl") -- initialization
# _restoreline("some\ntext\n")   -- calculate and return line number
{ my ($line, $filename);
  sub _restoreline {    ## no critic(RequireArgUnpacking)
    if (@_ == 2) {
        ($line, $filename) = @_;
    } else {
        $line += $_[0] =~ tr/\n//;
    }
    return("\n#line $line \"$filename\"\n");
  }
}

sub render :Export {
    my ($tmpl, %p) = @_;
    my $path = $tmpl =~ m{\A\.?/}xms ? $tmpl : "$TMPL_DIR$tmpl";
    1 while $path =~ s{(\A|/) (?!\.\.?/) [^/]+/\.\./}{$1}xms; ## no critic(ProhibitPostfixControls)
    $CACHE{$path} ||= tmpl2code($tmpl);
    return ${ $CACHE{$path}->(%p) };
}

sub tmpl2code :Export {
    my ($tmpl) = @_;
    my $path = $tmpl =~ m{\A\.?/}xms ? $tmpl : "$TMPL_DIR$tmpl";
    1 while $path =~ s{(\A|/) (?!\.\.?/) [^/]+/\.\./}{$1}xms; ## no critic(ProhibitPostfixControls)
    my $dir = $path;
    $dir =~ s{/[^/]*\z}{/}xms;
    my $e
        = 'package '.scalar(caller).'; use warnings; use strict;'
        . 'sub {'
        . 'local $'.__PACKAGE__.'::__ = q{};'
        . 'local $'.__PACKAGE__."::TMPL_DIR = \"\Q$dir\E\";"
        . 'local %_ = @_;'
        . _restoreline(1, $path)
        ;
    open my $fh, '<', $path or croak "open: $!";
    my $s = do { local $/ = undef; <$fh> };
    close $fh or croak "close: $!";
    while ( 1 ) {
        ($s=~/\G<!--&(.*?)-->/xmsgc)    && do {
            $e .= "$1;";
            $e .= _restoreline($1);
            }
     || ($s=~/\G&~(.*?)~&/xmsgc)        && do {
            $e .= "$1;";
            $e .= _restoreline($1);
            }
     || ($s=~/\G@~(.*?)~@/xmsgc)        && do {
            $e .= q{$}.__PACKAGE__.'::__ .= '.__PACKAGE__."::_utf8_encode(HTML::Entities::encode_entities(''.(do { $1; }), ".__PACKAGE__.'::UNSAFE_HTML)) ;';
            $e .= _restoreline($1);
            }
     || ($s=~/\G\#~(.*?)~\#/xmsgc)      && do {
            $e .= q{$}.__PACKAGE__.'::__ .= '.__PACKAGE__."::_utf8_encode(do { $1; }) ;";
            $e .= _restoreline($1);
            }
     || ($s=~/\G\^~(.*?)~\^/xmsgc)      && do {
            $e .= q{$}.__PACKAGE__.'::__ .= '.__PACKAGE__."::_utf8_encode(URI::Escape::uri_escape_utf8(''.(do { $1; }))) ;";
            $e .= _restoreline($1);
            }
     || ($s=~/\G(.*?)(?=<!--&|&~|@~|\#~|\^~|\n|$)(\n?)/xmsgc) && do {
            $e .= q{$}.__PACKAGE__."::__ .= \"\Q$1\E" . ($2 ? '\n' : q{}) . "\";$2";
            _restoreline($1.$2);
            }
     || last;
    }
    $e .= '; return \$'.__PACKAGE__.'::__ }';
    my $code = eval $e; ## no critic(ProhibitStringyEval)
    croak $@ if $@;
    return $code;
}

sub encode_js :Export {
    my ($s) = @_;
    $s = quotemeta $s;
    $s =~ s/\n/n/xmsg;
    return $s;
}

sub encode_js_data :Export {
    my ($s) = @_;
    $s = encode_json($s);
    $s =~ s{</script}{<\\/script}xmsg;
    return $s;
}

# faster than Encode::encode() and doesn't require temp var before append to $__
sub _utf8_encode {  ## no critic(ProhibitUnusedPrivateSubroutines)
    my ($s) = @_;
    utf8::encode($s);
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

Copyright 2007-2010 Alex Efros <powerman-asdf@ya.ru>.

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

