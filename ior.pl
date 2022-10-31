#!/usr/bin/env perl

use strict;

use Mojolicious::Lite -signatures;
use Mojo::UserAgent;
use Mojo::JSON qw(to_json from_json);

$ENV{MOJO_REVERSE_PROXY} = 1;

app->secrets(['0yluuekPAej7vBkp1BPVE78X7jggDu5p']);

app->log->info("Starting app...");

my $app_dir = app->home;

plugin 'Config';

my $kommunenr = app->config->{kommunenr};
my $app_id    = app->config->{app_id} // 'AE13DEEC-804F-4615-A74E-B4FAC11F0A30';
my $gatenavn  = app->config->{gatenavn};
my $gatekode  = app->config->{gatekode};
my $husnr     = app->config->{husnr};

my $ua = Mojo::UserAgent->new();

hook 'before_dispatch' => sub ($c) {
    if (my $host = $c->req->headers->header('X-Forwarded-Host')) {
	$c->req->url->base
	  (Mojo::URL->new
	   (($c->req->headers->header('X-Forwarded-Proto') || 'http')
	    . "://" . $host
	   ));
    }
};

get '/' => sub ($c) {
    my($data,$frak);

    my($tx,$res);

    $tx = $ua->get('https://komteksky.norkart.no/komtek.renovasjonwebapi/api/tommekalender/',
		   {
		    RenovasjonAppKey => $app_id,
		    Kommunenr => $kommunenr,
		   },
		   form => {
			    kommunenr => $kommunenr,
			    gatenavn => $gatenavn,
			    gatekode => $gatekode,
			    husnr => $husnr,
			   },
		  );

    $res = $tx->result;
    if ($res->is_success) {
	printf "Got it!\n";
	my $json = $res->json;
	for my $f (@$json) {
	    my $id = $f->{FraksjonId};
	    my $fh = $frak->{$id} //= { id => $id };
	    for my $d (@{$f->{Tommedatoer}}) {
		push @{$data->{$d}}, $fh;
	    }
	}
    }

    if ($frak) {
	$tx = $ua->get('https://komteksky.norkart.no/komtek.renovasjonwebapi/api/fraksjoner/',
		       {
			RenovasjonAppKey => $app_id,
			Kommunenr => $kommunenr,
		       });

	$res = $tx->result;
	if ($res->is_success) {
	    my $json = $res->json;

	    for my $f (@$json) {
		my $id = $f->{Id};
		if ($frak->{$id}) {
		    my $name = $f->{Navn};

		    for ($name) {
			s,-/,/,g;
			s/-emballasje//g;
		    }

		    $frak->{$id}{name} = $name;
		    $frak->{$id}{icon} = $f->{Ikon};
		}
	    }
	}
    }

    my $ret;

    for my $date (sort keys %$data) {
	push @$ret, { date => $date,
		      types => join(", ",
				    map { $_->{name} }
				    sort { $a->{id} <=> $b->{id} }
				    @{$data->{$date}}
				   ),
		    };
    }

    $c->render(json => { next_pickup_days => $ret });
};

app->start;
__DATA__
