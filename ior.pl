#!/usr/bin/env perl

use strict;

use Mojolicious::Lite -signatures;
use Mojo::UserAgent;
use Mojo::JSON qw(to_json from_json);
use Date::Parse;
use POSIX;

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

    # https://norkartrenovasjon.azurewebsites.net/proxyserver.ashx?server=https://komteksky.norkart.no/MinRenovasjon.Api/api/tommekalender/

    # $tx = $ua->get('https://komteksky.norkart.no/komtek.renovasjonwebapi/api/tommekalender/',
    #		   {
    #		    RenovasjonAppKey => $app_id,
    #		    Kommunenr => $kommunenr,
    #		   },
    #		   form => {
    #			    kommunenr => $kommunenr,
    #			    gatenavn => $gatenavn,
    #			    gatekode => $gatekode,
    #			    husnr => $husnr,
    #			   },
    #		  );

    my $form = {
		kommunenr => $kommunenr,
		gatenavn => $gatenavn,
		gatekode => $gatekode,
		husnr => $husnr,
	       };
    my $url = "https://komteksky.norkart.no/MinRenovasjon.Api/api/tommekalender/?".
      join("&", map { $_."=".$form->{$_} } keys %$form);

    $tx = $ua->get('https://norkartrenovasjon.azurewebsites.net/proxyserver.ashx',
		   {
		    RenovasjonAppKey => $app_id,
		    Kommunenr => $kommunenr,
		   },
		   form => {
			    server => $url,
			   }
		  );

    $res = $tx->result;
    if ($res->is_success) {
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
	$tx = $ua->get('https://norkartrenovasjon.azurewebsites.net/proxyserver.ashx',
		       {
			RenovasjonAppKey => $app_id,
			Kommunenr => $kommunenr,
		       },
		       form => {
				server => 'https://komteksky.norkart.no/MinRenovasjon.Api/api/fraksjoner/',
			       },
		      );

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

    my @now = localtime;

    for my $date (sort keys %$data) {
	my $time = str2time($date);
	my @time = localtime $time;
	my $fulldate = strftime("%Y-%m-%dT%H:%M:%S%z", @time);

	my $d = { date => $fulldate,
		  types => join(", ",
				map { $_->{name} }
				sort { $a->{id} <=> $b->{id} }
				@{$data->{$date}}
			       ),
		};

	my $human = "";
	my $ddiff = $time[7]-$now[7];

	if ($ddiff == 1) {
	    $human .= "i morgen ";
	}
	elsif ($ddiff == 0) {
	    $human .= "i dag ";
	}

	$human .= (qw( søndag mandag tirsdag onsdag torsdag fredag lørdag))[$time[6]];
	$human .= " " . $time[3];
	$human .= ". ";
	$human .= (qw(januar februar mars april mai juni juli august september oktober november desember))[$time[4]];
	$human .= " hentes " . $d->{types};
	$human =~ s/(.*),/$1 og/;

	$d->{human} = "\u\L$human";
	push @$ret, $d;
    }

    $c->render(json => { next_pickup_days => $ret });
};

app->start;
__DATA__
