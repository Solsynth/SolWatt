// The drive (ported 1:1 from Solian) imports `core/network.dart`. SolWatt's
// network layer lives at the package root, so re-export it wholesale to keep
// the ported imports intact without duplicating the client.
export 'package:solwatt/network.dart';
