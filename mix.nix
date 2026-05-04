{ lib, beamPackages, overrides ? (x: y: {}) }:

let
  buildRebar3 = lib.makeOverridable beamPackages.buildRebar3;
  buildMix = lib.makeOverridable beamPackages.buildMix;
  buildErlangMk = lib.makeOverridable beamPackages.buildErlangMk;

  self = packages // (overrides self packages);

  packages = with beamPackages; with self; {
    acceptor_pool = buildRebar3 rec {
      name = "acceptor_pool";
      version = "1.0.1";

      src = fetchHex {
        pkg = "acceptor_pool";
        version = "${version}";
        sha256 = "f172f3d74513e8edd445c257d596fc84dbdd56d2c6fa287434269648ae5a421e";
      };

      beamDeps = [];
    };

    ash = buildMix rec {
      name = "ash";
      version = "3.24.3";

      src = fetchHex {
        pkg = "ash";
        version = "${version}";
        sha256 = "c1022f8c549632137cbc8956f07bb4981405297f5abe7a752b4dffac175c3381";
      };

      beamDeps = [ crux decimal ecto ets jason plug reactor spark splode stream_data telemetry ];
    };

    chatterbox = buildRebar3 rec {
      name = "chatterbox";
      version = "0.15.1";

      src = fetchHex {
        pkg = "ts_chatterbox";
        version = "${version}";
        sha256 = "4f75b91451338bc0da5f52f3480fa6ef6e3a2aeecfc33686d6b3d0a0948f31aa";
      };

      beamDeps = [ hpack ];
    };

    cowboy = buildErlangMk rec {
      name = "cowboy";
      version = "2.14.2";

      src = fetchHex {
        pkg = "cowboy";
        version = "${version}";
        sha256 = "569081da046e7b41b5df36aa359be71a0c8874e5b9cff6f747073fc57baf1ab9";
      };

      beamDeps = [ cowlib ranch ];
    };

    cowlib = buildRebar3 rec {
      name = "cowlib";
      version = "2.16.0";

      src = fetchHex {
        pkg = "cowlib";
        version = "${version}";
        sha256 = "7f478d80d66b747344f0ea7708c187645cfcc08b11aa424632f78e25bf05db51";
      };

      beamDeps = [];
    };

    crux = buildMix rec {
      name = "crux";
      version = "0.1.2";

      src = fetchHex {
        pkg = "crux";
        version = "${version}";
        sha256 = "563ea3748ebfba9cc078e6d198a1d6a06015a8fae503f0b721363139f0ddb350";
      };

      beamDeps = [ stream_data ];
    };

    ctx = buildRebar3 rec {
      name = "ctx";
      version = "0.6.0";

      src = fetchHex {
        pkg = "ctx";
        version = "${version}";
        sha256 = "a14ed2d1b67723dbebbe423b28d7615eb0bdcba6ff28f2d1f1b0a7e1d4aa5fc2";
      };

      beamDeps = [];
    };

    decimal = buildMix rec {
      name = "decimal";
      version = "2.3.0";

      src = fetchHex {
        pkg = "decimal";
        version = "${version}";
        sha256 = "a4d66355cb29cb47c3cf30e71329e58361cfcb37c34235ef3bf1d7bf3773aeac";
      };

      beamDeps = [];
    };

    ecto = buildMix rec {
      name = "ecto";
      version = "3.13.5";

      src = fetchHex {
        pkg = "ecto";
        version = "${version}";
        sha256 = "df9efebf70cf94142739ba357499661ef5dbb559ef902b68ea1f3c1fabce36de";
      };

      beamDeps = [ decimal jason telemetry ];
    };

    ets = buildMix rec {
      name = "ets";
      version = "0.9.0";

      src = fetchHex {
        pkg = "ets";
        version = "${version}";
        sha256 = "2861fdfb04bcaeff370f1a5904eec864f0a56dcfebe5921ea9aadf2a481c822b";
      };

      beamDeps = [];
    };

    finch = buildMix rec {
      name = "finch";
      version = "0.21.0";

      src = fetchHex {
        pkg = "finch";
        version = "${version}";
        sha256 = "87dc6e169794cb2570f75841a19da99cfde834249568f2a5b121b809588a4377";
      };

      beamDeps = [ mime mint nimble_options nimble_pool telemetry ];
    };

    flow = buildMix rec {
      name = "flow";
      version = "1.2.4";

      src = fetchHex {
        pkg = "flow";
        version = "${version}";
        sha256 = "874adde96368e71870f3510b91e35bc31652291858c86c0e75359cbdd35eb211";
      };

      beamDeps = [ gen_stage ];
    };

    gen_stage = buildMix rec {
      name = "gen_stage";
      version = "1.3.2";

      src = fetchHex {
        pkg = "gen_stage";
        version = "${version}";
        sha256 = "0ffae547fa777b3ed889a6b9e1e64566217413d018cabd825f786e843ffe63e7";
      };

      beamDeps = [];
    };

    googleapis = buildMix rec {
      name = "googleapis";
      version = "0.1.0";

      src = fetchHex {
        pkg = "googleapis";
        version = "${version}";
        sha256 = "1989a7244fd17d3eb5f3de311a022b656c3736b39740db46506157c4604bd212";
      };

      beamDeps = [ protobuf ];
    };

    gproc = buildRebar3 rec {
      name = "gproc";
      version = "0.9.1";

      src = fetchHex {
        pkg = "gproc";
        version = "${version}";
        sha256 = "905088e32e72127ed9466f0bac0d8e65704ca5e73ee5a62cb073c3117916d507";
      };

      beamDeps = [];
    };

    grpc = buildMix rec {
      name = "grpc";
      version = "0.11.5";

      src = fetchHex {
        pkg = "grpc";
        version = "${version}";
        sha256 = "0a5d8673ef16649bef0903bca01c161acfc148e4d269133b6834b2af1f07f45e";
      };

      beamDeps = [ cowboy cowlib flow googleapis gun jason mint protobuf telemetry ];
    };

    grpcbox = buildRebar3 rec {
      name = "grpcbox";
      version = "0.17.1";

      src = fetchHex {
        pkg = "grpcbox";
        version = "${version}";
        sha256 = "4a3b5d7111daabc569dc9cbd9b202a3237d81c80bf97212fbc676832cb0ceb17";
      };

      beamDeps = [ acceptor_pool chatterbox ctx gproc ];
    };

    gun = buildRebar3 rec {
      name = "gun";
      version = "2.2.0";

      src = fetchHex {
        pkg = "gun";
        version = "${version}";
        sha256 = "76022700c64287feb4df93a1795cff6741b83fb37415c40c34c38d2a4645261a";
      };

      beamDeps = [ cowlib ];
    };

    hpack = buildRebar3 rec {
      name = "hpack";
      version = "0.3.0";

      src = fetchHex {
        pkg = "hpack_erl";
        version = "${version}";
        sha256 = "d6137d7079169d8c485c6962dfe261af5b9ef60fbc557344511c1e65e3d95fb0";
      };

      beamDeps = [];
    };

    hpax = buildMix rec {
      name = "hpax";
      version = "1.0.3";

      src = fetchHex {
        pkg = "hpax";
        version = "${version}";
        sha256 = "8eab6e1cfa8d5918c2ce4ba43588e894af35dbd8e91e6e55c817bca5847df34a";
      };

      beamDeps = [];
    };

    iterex = buildMix rec {
      name = "iterex";
      version = "0.1.2";

      src = fetchHex {
        pkg = "iterex";
        version = "${version}";
        sha256 = "2e103b8bcc81757a9af121f6dc0df312c9a17220f302b1193ef720460d03029d";
      };

      beamDeps = [];
    };

    jason = buildMix rec {
      name = "jason";
      version = "1.4.4";

      src = fetchHex {
        pkg = "jason";
        version = "${version}";
        sha256 = "c5eb0cab91f094599f94d55bc63409236a8ec69a21a67814529e8d5f6cc90b3b";
      };

      beamDeps = [ decimal ];
    };

    jose = buildMix rec {
      name = "jose";
      version = "1.11.12";

      src = fetchHex {
        pkg = "jose";
        version = "${version}";
        sha256 = "31e92b653e9210b696765cdd885437457de1add2a9011d92f8cf63e4641bab7b";
      };

      beamDeps = [];
    };

    libgraph = buildMix rec {
      name = "libgraph";
      version = "0.16.0";

      src = fetchHex {
        pkg = "libgraph";
        version = "${version}";
        sha256 = "41ca92240e8a4138c30a7e06466acc709b0cbb795c643e9e17174a178982d6bf";
      };

      beamDeps = [];
    };

    mime = buildMix rec {
      name = "mime";
      version = "2.0.7";

      src = fetchHex {
        pkg = "mime";
        version = "${version}";
        sha256 = "6171188e399ee16023ffc5b76ce445eb6d9672e2e241d2df6050f3c771e80ccd";
      };

      beamDeps = [];
    };

    mint = buildMix rec {
      name = "mint";
      version = "1.7.1";

      src = fetchHex {
        pkg = "mint";
        version = "${version}";
        sha256 = "fceba0a4d0f24301ddee3024ae116df1c3f4bb7a563a731f45fdfeb9d39a231b";
      };

      beamDeps = [ hpax ];
    };

    mox = buildMix rec {
      name = "mox";
      version = "1.2.0";

      src = fetchHex {
        pkg = "mox";
        version = "${version}";
        sha256 = "c7b92b3cc69ee24a7eeeaf944cd7be22013c52fcb580c1f33f50845ec821089a";
      };

      beamDeps = [ nimble_ownership ];
    };

    nimble_options = buildMix rec {
      name = "nimble_options";
      version = "1.1.1";

      src = fetchHex {
        pkg = "nimble_options";
        version = "${version}";
        sha256 = "821b2470ca9442c4b6984882fe9bb0389371b8ddec4d45a9504f00a66f650b44";
      };

      beamDeps = [];
    };

    nimble_ownership = buildMix rec {
      name = "nimble_ownership";
      version = "1.0.2";

      src = fetchHex {
        pkg = "nimble_ownership";
        version = "${version}";
        sha256 = "098af64e1f6f8609c6672127cfe9e9590a5d3fcdd82bc17a377b8692fd81a879";
      };

      beamDeps = [];
    };

    nimble_pool = buildMix rec {
      name = "nimble_pool";
      version = "1.1.0";

      src = fetchHex {
        pkg = "nimble_pool";
        version = "${version}";
        sha256 = "af2e4e6b34197db81f7aad230c1118eac993acc0dae6bc83bac0126d4ae0813a";
      };

      beamDeps = [];
    };

    oidcc = buildMix rec {
      name = "oidcc";
      version = "3.7.2";

      src = fetchHex {
        pkg = "oidcc";
        version = "${version}";
        sha256 = "e3f1ed91509fdeb31ec8b9de4ecda0e80cb68b463a9f5b7a9ee1ee40e521e445";
      };

      beamDeps = [ jose telemetry telemetry_registry ];
    };

    opentelemetry = buildRebar3 rec {
      name = "opentelemetry";
      version = "1.7.0";

      src = fetchHex {
        pkg = "opentelemetry";
        version = "${version}";
        sha256 = "a9173b058c4549bf824cbc2f1d2fa2adc5cdedc22aa3f0f826951187bbd53131";
      };

      beamDeps = [ opentelemetry_api ];
    };

    opentelemetry_api = buildMix rec {
      name = "opentelemetry_api";
      version = "1.5.0";

      src = fetchHex {
        pkg = "opentelemetry_api";
        version = "${version}";
        sha256 = "f53ec8a1337ae4a487d43ac89da4bd3a3c99ddf576655d071deed8b56a2d5dda";
      };

      beamDeps = [];
    };

    opentelemetry_exporter = buildRebar3 rec {
      name = "opentelemetry_exporter";
      version = "1.10.0";

      src = fetchHex {
        pkg = "opentelemetry_exporter";
        version = "${version}";
        sha256 = "33a116ed7304cb91783f779dec02478f887c87988077bfd72840f760b8d4b952";
      };

      beamDeps = [ grpcbox opentelemetry opentelemetry_api tls_certificate_check ];
    };

    opentelemetry_telemetry = buildMix rec {
      name = "opentelemetry_telemetry";
      version = "1.1.2";

      src = fetchHex {
        pkg = "opentelemetry_telemetry";
        version = "${version}";
        sha256 = "641ab469deb181957ac6d59bce6e1321d5fe2a56df444fc9c19afcad623ab253";
      };

      beamDeps = [ opentelemetry_api telemetry ];
    };

    plug = buildMix rec {
      name = "plug";
      version = "1.19.1";

      src = fetchHex {
        pkg = "plug";
        version = "${version}";
        sha256 = "560a0017a8f6d5d30146916862aaf9300b7280063651dd7e532b8be168511e62";
      };

      beamDeps = [ mime plug_crypto telemetry ];
    };

    plug_crypto = buildMix rec {
      name = "plug_crypto";
      version = "2.1.1";

      src = fetchHex {
        pkg = "plug_crypto";
        version = "${version}";
        sha256 = "6470bce6ffe41c8bd497612ffde1a7e4af67f36a15eea5f921af71cf3e11247c";
      };

      beamDeps = [];
    };

    protobuf = buildMix rec {
      name = "protobuf";
      version = "0.16.0";

      src = fetchHex {
        pkg = "protobuf";
        version = "${version}";
        sha256 = "f0d0d3edd8768130f24cc2cfc41320637d32c80110e80d13f160fa699102c828";
      };

      beamDeps = [ jason ];
    };

    ranch = buildRebar3 rec {
      name = "ranch";
      version = "2.2.0";

      src = fetchHex {
        pkg = "ranch";
        version = "${version}";
        sha256 = "fa0b99a1780c80218a4197a59ea8d3bdae32fbff7e88527d7d8a4787eff4f8e7";
      };

      beamDeps = [];
    };

    reactor = buildMix rec {
      name = "reactor";
      version = "1.0.1";

      src = fetchHex {
        pkg = "reactor";
        version = "${version}";
        sha256 = "3497db2b204c9a3cabdaf1b26d2405df1dfbb138ce0ce50e616e9db19fec0043";
      };

      beamDeps = [ iterex jason libgraph spark splode telemetry yaml_elixir ymlr ];
    };

    req = buildMix rec {
      name = "req";
      version = "0.5.17";

      src = fetchHex {
        pkg = "req";
        version = "${version}";
        sha256 = "0b8bc6ffdfebbc07968e59d3ff96d52f2202d0536f10fef4dc11dc02a2a43e39";
      };

      beamDeps = [ finch jason mime plug ];
    };

    snabbkaffe = buildRebar3 rec {
      name = "snabbkaffe";
      version = "1.0.10";

      src = fetchHex {
        pkg = "snabbkaffe";
        version = "${version}";
        sha256 = "70a98df36ae756908d55b5770891d443d63c903833e3e87d544036e13d4fac26";
      };

      beamDeps = [];
    };

    spark = buildMix rec {
      name = "spark";
      version = "2.6.1";

      src = fetchHex {
        pkg = "spark";
        version = "${version}";
        sha256 = "77bbefa5263bb6b70e1195bc0fc662ddb8ef5937a356a77ae072e56983ad13f0";
      };

      beamDeps = [ jason ];
    };

    splode = buildMix rec {
      name = "splode";
      version = "0.3.1";

      src = fetchHex {
        pkg = "splode";
        version = "${version}";
        sha256 = "8f2309b6ec2ecbb01435656429ed1d9ed04ba28797a3280c3b0d1217018ecfbd";
      };

      beamDeps = [];
    };

    ssl_verify_fun = buildRebar3 rec {
      name = "ssl_verify_fun";
      version = "1.1.7";

      src = fetchHex {
        pkg = "ssl_verify_fun";
        version = "${version}";
        sha256 = "fe4c190e8f37401d30167c8c405eda19469f34577987c76dde613e838bbc67f8";
      };

      beamDeps = [];
    };

    stream_data = buildMix rec {
      name = "stream_data";
      version = "1.3.0";

      src = fetchHex {
        pkg = "stream_data";
        version = "${version}";
        sha256 = "3cc552e286e817dca43c98044c706eec9318083a1480c52ae2688b08e2936e3c";
      };

      beamDeps = [];
    };

    telemetry = buildRebar3 rec {
      name = "telemetry";
      version = "1.4.1";

      src = fetchHex {
        pkg = "telemetry";
        version = "${version}";
        sha256 = "2172e05a27531d3d31dd9782841065c50dd5c3c7699d95266b2edd54c2dafa1c";
      };

      beamDeps = [];
    };

    telemetry_metrics = buildMix rec {
      name = "telemetry_metrics";
      version = "1.1.0";

      src = fetchHex {
        pkg = "telemetry_metrics";
        version = "${version}";
        sha256 = "e7b79e8ddfde70adb6db8a6623d1778ec66401f366e9a8f5dd0955c56bc8ce67";
      };

      beamDeps = [ telemetry ];
    };

    telemetry_poller = buildRebar3 rec {
      name = "telemetry_poller";
      version = "1.3.0";

      src = fetchHex {
        pkg = "telemetry_poller";
        version = "${version}";
        sha256 = "51f18bed7128544a50f75897db9974436ea9bfba560420b646af27a9a9b35211";
      };

      beamDeps = [ telemetry ];
    };

    telemetry_registry = buildMix rec {
      name = "telemetry_registry";
      version = "0.3.2";

      src = fetchHex {
        pkg = "telemetry_registry";
        version = "${version}";
        sha256 = "e7ed191eb1d115a3034af8e1e35e4e63d5348851d556646d46ca3d1b4e16bab9";
      };

      beamDeps = [ telemetry ];
    };

    tls_certificate_check = buildRebar3 rec {
      name = "tls_certificate_check";
      version = "1.32.1";

      src = fetchHex {
        pkg = "tls_certificate_check";
        version = "${version}";
        sha256 = "e78a157966456b500a87a2fc29cffcd6dcfb5a26348c8372a2c5c0a8e5797f51";
      };

      beamDeps = [ ssl_verify_fun ];
    };

    yamerl = buildRebar3 rec {
      name = "yamerl";
      version = "0.10.0";

      src = fetchHex {
        pkg = "yamerl";
        version = "${version}";
        sha256 = "346adb2963f1051dc837a2364e4acf6eb7d80097c0f53cbdc3046ec8ec4b4e6e";
      };

      beamDeps = [];
    };

    yaml_elixir = buildMix rec {
      name = "yaml_elixir";
      version = "2.12.1";

      src = fetchHex {
        pkg = "yaml_elixir";
        version = "${version}";
        sha256 = "d9ac16563c737d55f9bfeed7627489156b91268a3a21cd55c54eb2e335207fed";
      };

      beamDeps = [ yamerl ];
    };

    ymlr = buildMix rec {
      name = "ymlr";
      version = "5.1.5";

      src = fetchHex {
        pkg = "ymlr";
        version = "${version}";
        sha256 = "7030cb240c46850caeb3b01be745307632be319b15f03083136f6251f49b516d";
      };

      beamDeps = [];
    };
  };
in self

