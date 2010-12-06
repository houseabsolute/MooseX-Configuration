package MooseX::Configuration::Trait::Object;

use Moose::Role;

use autodie;
use namespace::autoclean;

use Config::INI::Reader;
use List::AllUtils qw( uniq );
use MooseX::Types -declare => ['MaybeFile'];
use MooseX::Types::Moose qw( HashRef Maybe Str );
use MooseX::Types::Path::Class qw( File );
use Path::Class::File;
use Text::Autoformat qw( autoformat );

subtype MaybeFile,
    as Maybe[File];

coerce MaybeFile,
    from Str,
    via { Path::Class::File->new($_) };

has config_file => (
    is      => 'ro',
    isa     => MaybeFile,
    coerce  => 1,
    lazy    => 1,
    builder => '_build_config_file',
    clearer => '_clear_config_file',
);

has _raw_config => (
    is      => 'ro',
    isa     => HashRef [ HashRef [Str] ],
    lazy    => 1,
    builder => '_build_raw_config',
);

sub _build_config_file {
    die 'No config file was defined for this object';
}

sub _build_raw_config {
    my $self = shift;

    my $file = $self->config_file()
        or return {};

    return Config::INI::Reader->read_file($file) || {};
}

sub _from_config {
    my $self    = shift;
    my $section = shift;
    my $key     = shift;

    my $hash = $self->_raw_config();

    for my $key ( $section, $key ) {
        $hash = $hash->{$key};

        return unless defined $hash && length $hash;
    }

    if ( ref $hash ) {
        die
            "Config for $section - $key did not resolve to a non-reference value";
    }

    return $hash;
}

sub write_config_file {
    my $self = shift;
    my %p    = @_;

    my @sections;
    my %attrs_by_section;

    for my $attr (
        sort { $a->insertion_order() <=> $b->insertion_order() }
        grep { $_->can('config_section') } $self->meta()->get_all_attributes()
        ) {

        push @sections, $attr->config_section();
        push @{ $attrs_by_section{ $attr->config_section() } }, $attr;
    }

    my $content = q{};

    if ( $p{generated_by} ) {
        $content .= '; ' . $p{generated_by} . "\n\n";
    }

    for my $section ( uniq @sections ) {
        unless ( $section eq q{_} ) {
            $content .= '[' . $section . ']';
            $content .= "\n";
        }

        for my $attr ( @{ $attrs_by_section{$section} } ) {

            my $doc;
            if ( $attr->has_documentation() ) {
                $doc = autoformat( $attr->documentation() );
                $doc =~ s/\n\n+$/\n/;
                $doc =~ s/^/; /gm;
            }

            if ( $attr->is_required() ) {
                $doc .= "; This configuration key is required.\n";
            }

            if ( my $def = $attr->has_original_default() ) {
                $doc .= "; Defaults to $def\n";
            }

            $content .= $doc if defined $doc;

            my $value;
            if ( my $reader = $attr->get_read_method() ) {
                $value = $self->$reader();
            }

            my $key = $attr->config_key();

            if ( defined $value && length $value ) {
                $content .= "$key = $value\n";
            }
            else {
                $content .= "; $key =\n";
            }

            $content .= "\n";
        }
    }

    my $file = exists $p{file} ? $p{file} : $self->config_file();

    my $fh;

    if ( ref $file eq 'GLOB' || ref(\$file) eq 'GLOB' ) {
        $fh = $file;
    }
    else {
        open $fh, '>', $file;
    }

    print {$fh} $content;
    close $fh;
}

1;
