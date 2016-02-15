[![Build Status](https://travis-ci.org/powerman/perl-Text-MiniTmpl.svg?branch=master)](https://travis-ci.org/powerman/perl-Text-MiniTmpl)
[![Coverage Status](https://coveralls.io/repos/powerman/perl-Text-MiniTmpl/badge.svg?branch=master)](https://coveralls.io/r/powerman/perl-Text-MiniTmpl?branch=master)

# NAME

Text::MiniTmpl - Compile and render templates

# VERSION

This document describes Text::MiniTmpl version v1.1.6

# SYNOPSIS

    use Text::MiniTmpl qw( render );

    $html1 = render('template.html', %params1);
    $html2 = render('template.html', %params2);

# DESCRIPTION

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

- path relative to current template's directory: ` 'file', 'dir/file', '../file' `
- path relative to current working directory (where your script executed):
` './file', './dir/file' `
- absolute path: ` '/dir/file' `

When you render top-level template (i.e. call render() from your script,
not inside some template) paths ` 'file' ` and ` './file' `, ` 'dir/file' `
and ` './dir/file' ` are same.

Correctly report compile errors in templates, with template name and line
number.

## Unicode support

Files with templates should be in UTF8. Parameters for templates should be
perl Unicode scalars. Rendered template (returned by render() or by
function returned by tmpl2code()) will be in UTF8.

You can disable it using raw(1) (see below) to get more speed.

## Source Filters support

Probably not all filters will work inside templates - keep in mind filter
will see auto-generated (by tmpl2code()) perl function's code instead of
plain template text. See \`perldoc perlfilter\` for more details.

Example:

    &~ use Filter::CommaEquals; ~&
    &~ @{ $_{users} } ,= 'GHOST' ~&
    &~ for (@{ $_{users} }) { ~&
    <p>Hello, @~ $_ ~@!</p>
    &~ } ~&

## Template syntax

Any template become perl function after parsing. This function will accept
it parameters in ` %_ ` (it start with ` local %_ = @_; `).
Of course, you can use my() and local() variables in template (their scope
will be full template, not only placeholder's block where they was defined).

- &~ PERL CODE ~&
- &lt;!--& PERL CODE -->

    Execute PERL CODE but don't output anything.

- @~ PERL CODE ~@

    Execute PERL CODE and output it result (last calculated expression)
    escaped using HTML::Entities::encode\_entities().

- ^~ PERL CODE ~^

    Execute PERL CODE and output it result (last calculated expression)
    escaped using URI::Escape::uri\_escape\_utf8().

- #~ PERL CODE ~#

    Execute PERL CODE and output it result (last calculated expression)
    AS IS, without any escaping.

- any other text ...

    ... will be output AS IS

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

# EXPORTS

Nothing by default, but all documented functions can be explicitly imported.

# INTERFACE 

- render( $filename, %params )

    Render template from $filename with %params.

    This is caching wrapper around tmpl2code(), which avoid calling
    tmpl2code() second time for same $filename.

    Example:

        $html = render( 'template/index.html',
            title   => $title,
            name    => $name,
        );

    Return STRING with rendered template.

- tmpl2code( $filename )

    Read template from $filename (may be absolute or relative to current
    template's directory or current working directory - see ["DESCRIPTION"](#description)),
    compile it into ANON function.

    This function can be executed with ` ( %params ) ` parameters,
    it will render $filename template with given ` %params ` and return
    SCALARREF to rendered text.

    Example:

        $code = tmpl2code( 'template/index.html' );
        $html = ${ $code->( title=>$title, name=>$name ) };

    Return CODEREF to that function.

- raw( $is\_raw )

    If $is\_raw TRUE disable Unicode support.
    To enable Unicode again call raw() with $is\_raw FALSE.

    **Disabling Unicode support will speedup this module in about 1.5 times!**

    When Unicode support disabled your parameters used to render template will
    be used in template AS IS, without attempt to encode them to UTF8.
    This mean you shouldn't use perl Unicode scalars in these parameters anymore.

    This affect only templates processed by tmpl2code() after calling raw()
    (beware caching effect of render()).

- encode\_js( $scalar )

    Encode $scalar (string or number) for inserting into JavaScript code
    (usually inside HTML templates).

    Example:

        <script>
        var int_from_perl =  #~ encode_js($number) ~#;
        var str_from_perl = '#~ encode_js($string) ~#';
        </script>

    Return encoded string.

- encode\_js\_data( $complex )

    Encode $complex data structure (HASHREF, ARRAYREF, etc. - any data type
    supported by JSON::XS) for inserting into JavaScript code (usually inside
    HTML templates).

    Example:

        <script>
        var hash_from_perl  = #~ encode_js_data( \%hash ) ~#;
        var array_from_perl = #~ encode_js_data( \@array ) ~#;
        </script>

    Return encoded string.

# SPEED AND SIZE

This module implemented under 100 lines (about 3KB) of pure Perl code.
And while code is terse enough, I believe it still simple and clean.

While this is pure-perl module with many enough features, it's still very
fast - you can do your own benchmarking using cool [Template::Benchmark](https://metacpan.org/pod/Template::Benchmark)
module, here is results from my system:

- instance\_reuse

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

- uncached\_disk

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

# SUPPORT

## Bugs / Feature Requests

Please report any bugs or feature requests through the issue tracker
at [https://github.com/powerman/perl-Text-MiniTmpl/issues](https://github.com/powerman/perl-Text-MiniTmpl/issues).
You will be notified automatically of any progress on your issue.

## Source Code

This is open source software. The code repository is available for
public review and contribution under the terms of the license.
Feel free to fork the repository and submit pull requests.

[https://github.com/powerman/perl-Text-MiniTmpl](https://github.com/powerman/perl-Text-MiniTmpl)

    git clone https://github.com/powerman/perl-Text-MiniTmpl.git

## Resources

- MetaCPAN Search

    [https://metacpan.org/search?q=Text-MiniTmpl](https://metacpan.org/search?q=Text-MiniTmpl)

- CPAN Ratings

    [http://cpanratings.perl.org/dist/Text-MiniTmpl](http://cpanratings.perl.org/dist/Text-MiniTmpl)

- AnnoCPAN: Annotated CPAN documentation

    [http://annocpan.org/dist/Text-MiniTmpl](http://annocpan.org/dist/Text-MiniTmpl)

- CPAN Testers Matrix

    [http://matrix.cpantesters.org/?dist=Text-MiniTmpl](http://matrix.cpantesters.org/?dist=Text-MiniTmpl)

- CPANTS: A CPAN Testing Service (Kwalitee)

    [http://cpants.cpanauthors.org/dist/Text-MiniTmpl](http://cpants.cpanauthors.org/dist/Text-MiniTmpl)

# AUTHOR

Alex Efros &lt;powerman@cpan.org>

# COPYRIGHT AND LICENSE

This software is Copyright (c) 2007-2014 by Alex Efros &lt;powerman@cpan.org>.

This is free software, licensed under:

    The MIT (X11) License
