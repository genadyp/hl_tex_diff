#!/usr/bin/perl

use v5.10;

use Cwd;
use Cwd 'abs_path';
use File::Basename;
use File::Spec;
use File::Copy;

use Git::Repository;
use Getopt::Simple;

=head1 NAME

B<hl_tex_diff> - highlights diff of LaTeX files.
=cut

##########################
# General NOTEs and TODOs
##########################

=head1 NOTEs

=head2 LaTeX dependencies

 LaTeX framed package for shaded environment.
=cut

=head2 Limitations

 Changes in the existing figures are not highlighted
 - only new figures highlighted.
=cut

##########################
# Variables
##########################
my ($options) = {
  "tag|t" => {
    "type" => '=s',
    env => '-',
    verbose => 'not supported yet',
    default => '',
    order => '1'
  },
  git_dir => {
    type => '=s',
    env => '_',
    verbose =>
      'directory where git repository located (parnt of .git directory)',
    default => '',
    order => '2'
  }
};

use constant {
  HL_FILE_SUFFIX => q/_hl/
};

my $usage = "Usage: $0 [options] file_name";
my $options_parser;
my $file;
my $file_path;
my $repo;

##########################
# Methods
##########################
sub init {
  $options_parser = Getopt::Simple->new;
  parse_options();
  $options_parser->dumpOptions;

  my $git_dir_param = $options_parser->{'switch'}{'git_dir'};
  my $gitdir = File::Spec->catdir(abs_path($git_dir_param), '.git');
  $repo = Git::Repository->new(git_dir => $gitdir);

  $file_path = File::Spec->catfile($git_dir_param, $file);
}

sub parse_options {
  if (! $options_parser->getOptions($options, $usage)) {
    exit(-1);
  }

  my $git_dir_param = $options_parser->{'switch'}{'git_dir'};
  unless ($git_dir_param && -d $git_dir_param) {
    die "git_dir is absent or not a directory";
  }

  $file = shift @ARGV;
  unless ($file && -f File::Spec->catfile($git_dir_param, $file)) {
    die "File name must be provided: ", $file;
  }

}

sub diff {
  my $cmd = $repo->command(diff => $file);
  my @diff_out = $cmd->stdout->getlines;
  $cmd->close;
  return \@diff_out;
}

sub hl_file {
  my ($diff_out) = @_;
  use constant {
    HL_START => q/\begin{shaded}/,
    HL_END   => q/\end{shaded}/
  };

  my $diff_out_idx = -1;
  my @hl_tex = ();

  my $cur_added_line;

  my $set_cur_added_line = sub {
    #while(($cur_added_line = $diff_fh->getline) &&
    #!is_diff_added_line($cur_added_line)) {}
    $cur_added_line = undef;  # for the case that end of array reached
    for($diff_out_idx++; $diff_out_idx < @$diff_out; $diff_out_idx++) {
      $cur_added_line = $diff_out->[$diff_out_idx];
      if (is_diff_added_line($cur_added_line)) {
        $cur_added_line = remove_git_signs($cur_added_line);

        chomp $cur_added_line;
        if($cur_added_line =~ /^\s*$/) {
          # new lines that contain only while spaces
          # will be omitted
          next;
        } else {
          last;
        }
      }
    }
  };

  my $is_end_of_diff_add_block = sub {
    return $diff_out_idx == @$diff_out ||
           !is_diff_added_line($diff_out->[$diff_out_idx+1]);
  };

  $set_cur_added_line->();
  unless ($cur_added_line) {
    save_highlighted();
  }

  open(my $fh, "<", $file_path) or die "$!";
  my $is_in_hl_block = undef;
  my $is_new_figure = undef;

  # FIXME begin command general fix, including figure
  while (my $orig_tex_line = <$fh>) {
    chomp $orig_tex_line;
    if ($cur_added_line && $orig_tex_line =~ /\Q$cur_added_line\E/) {
      if ($orig_tex_line =~ /\s*\\begin{figure}/) {
        if ($is_in_hl_block) {
          push @hl_tex, HL_END;
          $is_in_hl_block = undef;
        }
        push @hl_tex, $orig_tex_line;
        push @hl_tex, HL_START;
        $is_new_figure = 1;
      } elsif ($is_new_figure && $orig_tex_line =~ /\s*\\end{figure}/) {
        push @hl_tex, HL_END;
        push @hl_tex, $orig_tex_line;
        $is_new_figure = undef;
      } elsif ($is_new_figure) {
        push @hl_tex, $orig_tex_line;
      } else {
        if (!$is_in_hl_block) {
          push @hl_tex, HL_START;
          $is_in_hl_block = 1;
        }
        push @hl_tex, $orig_tex_line;
        if($is_end_of_diff_add_block->()) {
          push @hl_tex, HL_END;
          $is_in_hl_block = undef;
        }
      }
      $set_cur_added_line->();
    } else {
      # the case when new empty line added
      if (!$cur_added_line && $is_in_hl_block) {
        push @hl_tex, HL_END;
        $is_in_hl_block = undef;
      }
      push @hl_tex, $orig_tex_line;
    }
  }
  close $fh;

  save_highlighted(\@hl_tex);
}

sub is_diff_added_line {
  my ($line) = @_;
  return $line && $line =~ /^\+[^+]/;
}

sub remove_git_signs {
  my ($line) = @_;
  $line =~ s/^(-|\+)[^-+]//;
  return $line;
}

sub save_highlighted {
  my ($content) = @_;
  my ($fname, $path, $suffix) = fileparse($file_path, qr/\.\w+$/);
  my $res_fname = join('', $fname, HL_FILE_SUFFIX, $suffix);
  my $res_path = File::Spec->catfile($path, $res_fname);

  say "Saving highlighted into ", $res_path, " ...";
  if ($content) {
    open(my $res_fh, ">", $res_path) or die "$!";
    foreach my $line (@$content) {
      say $res_fh $line;
    }
    close $res_fh;
  } else {
    warn "No highlighting was found - just copy";
    copy ($file_path, $res_path) or die "$!";
  }
  say "Saving finished";
}
##########################
# Main
##########################
init();
my $diff_out = diff();
hl_file($diff_out);

