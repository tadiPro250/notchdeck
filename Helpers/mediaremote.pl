# Loads NotchDeck's MediaRemote bridge into this (Apple-signed) perl and runs one entry point.
use strict;
use DynaLoader;
my ($library, $mode) = @ARGV;
my $handle = DynaLoader::dl_load_file($library, 0) or die "load failed: " . DynaLoader::dl_error();
my $symbol = DynaLoader::dl_find_symbol($handle, $mode eq 'send' ? 'notchdeck_send' : 'notchdeck_stream')
    or die "symbol missing";
DynaLoader::dl_install_xsub('main::entry', $symbol);
entry();
exit 0;
