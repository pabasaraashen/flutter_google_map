import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {

  Location _locationController = new Location();

  static const LatLng _pGooglePlex = LatLng(6.927079, 79.861244);
  static const LatLng _pApplePark = LatLng(6.933850, 79.844860);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GoogleMap(
        initialCameraPosition: const CameraPosition(
          target: _pGooglePlex,
          zoom: 12,
        ),
        markers: {
          Marker(
            markerId: const MarkerId("_currentLocation"),
            icon: BitmapDescriptor.defaultMarker,
            position: _pGooglePlex,
          ),
          Marker(
            markerId: const MarkerId("_sourceLocation"),
            icon: BitmapDescriptor.defaultMarker,
            position: _pApplePark,
          ),
        },
      ),
    );
  }

  Future<void> getLocationUpdates() async {
    bool _serviceEnabled;
    PermissionStatus _permissionGranted;

    _serviceEnabled = await _locationController.serviceEnabled();
    if (_serviceEnabled) {
      _serviceEnabled = await _locationController.requestService();
    }else{
      return;
    }
  }
}
