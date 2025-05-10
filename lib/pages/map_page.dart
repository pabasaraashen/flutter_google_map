import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:google_place/google_place.dart';
import 'package:location/location.dart' as loc;
import 'package:http/http.dart' as http;
import 'dart:convert';
// Import the components
import 'trans_searchbar/trans_searchbar.dart';
import 'travelinfo_panel/travelinfo_panel.dart';

const String GOOGLE_MAPS_API_KEY = "AIzaSyDPPGBYGwYTOrWtL9dNmiXkjhrsGS6sFTY"; // google map API

// transportation cost calculation
const double CAR_BASE_FARE = 120.0;
const double CAR_COST_PER_KM = 100.0;

const double THREEWHEEL_BASE_FARE = 50.0;
const double THREEWHEEL_COST_PER_KM = 40.0;

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final loc.Location _locationController = loc.Location();
  final Completer<GoogleMapController> _mapController = Completer<GoogleMapController>();
  final TextEditingController _searchController = TextEditingController();

  LatLng? _currentP;
  LatLng? _destinationP;

  Map<PolylineId, Polyline> polylines = {};
  Map<MarkerId, Marker> markers = {};
  late GooglePlace googlePlace;

  String? travelTime;
  String? travelDistance;
  String? transportationCost;

  // Transportation mode
  String selectedMode = 'car';

  // Raw values for calculation
  double? distanceInKm;

  @override
  void initState() {
    super.initState();
    googlePlace = GooglePlace('AIzaSyBbLd67HZT9EYb8Xi7ySuVWJVBmLRFREjM'); // google place API
    getLocationUpdates();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _currentP == null
          ? const Center(child: Text("Loading..."))
          : Stack(
        children: [
          GoogleMap(
            onMapCreated: (controller) => _mapController.complete(controller),
            initialCameraPosition: CameraPosition(target: _currentP!, zoom: 11),
            markers: Set<Marker>.of(markers.values),
            polylines: Set<Polyline>.of(polylines.values),
          ),

          // Search Bar (using the TransSearchBar component)
          Positioned(
            top: 50,
            left: 15,
            right: 15,
            child: TransSearchBar(
              searchController: _searchController,
              googlePlace: googlePlace,
              onLocationSelected: (LatLng newPos) {
                setState(() {
                  _destinationP = newPos;
                });

                _cameraToPosition(newPos);

                // Draw route to the selected destination
                if (_currentP != null) {
                  updateDirections(_currentP!, _destinationP!);
                }
              },
            ),
          ),

          // Transportation mode button selection
          Positioned(
            top: 120,
            right: 15,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    spreadRadius: 1,
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
              child: Column(
                children: [
                  _transportModeButton('car', Icons.directions_car),
                  const SizedBox(height: 8),
                  _transportModeButton('threewheel', Icons.local_taxi),
                ],
              ),
            ),
          ),

          // Travel Information Panel (using the TravelInfoPanel component)
          if (travelTime != null && travelDistance != null)
            Positioned(
              bottom: 50,
              left: 20,
              right: 20,
              child: TravelInfoPanel(
                travelTime: travelTime,
                travelDistance: travelDistance,
                transportationCost: transportationCost,
                selectedMode: selectedMode,
              ),
            ),
        ],
      ),
    );
  }

  Widget _transportModeButton(String mode, IconData icon) {
    bool isSelected = selectedMode == mode;

    return GestureDetector(
      onTap: () {
        setState(() {
          selectedMode = mode;

          // Recalculate cost if destination is already set
          if (_currentP != null && _destinationP != null && distanceInKm != null) {
            transportationCost = calculateTransportationCost(distanceInKm!, selectedMode);
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue : Colors.white,
          shape: BoxShape.circle,
          boxShadow: isSelected ? [
            BoxShadow(
              color: Colors.blue.withOpacity(0.4),
              spreadRadius: 1,
              blurRadius: 4,
            )
          ] : null,
        ),
        child: Icon(
          icon,
          color: isSelected ? Colors.white : Colors.grey,
          size: 24,
        ),
      ),
    );
  }

  Future<void> _cameraToPosition(LatLng pos) async {
    final GoogleMapController controller = await _mapController.future;
    CameraPosition _newCameraPosition = CameraPosition(target: pos, zoom: 11);
    await controller.animateCamera(CameraUpdate.newCameraPosition(_newCameraPosition));
  }

  Future<void> getLocationUpdates() async {
    bool _serviceEnabled = await _locationController.serviceEnabled();
    if (!_serviceEnabled) {
      _serviceEnabled = await _locationController.requestService();
      if (!_serviceEnabled) return;
    }

    PermissionStatus _permissionGranted = await _locationController.hasPermission();
    if (_permissionGranted == PermissionStatus.denied) {
      _permissionGranted = await _locationController.requestPermission();
      if (_permissionGranted != PermissionStatus.granted) return;
    }

    _locationController.onLocationChanged.listen((LocationData currentLocation) {
      if (currentLocation.latitude != null && currentLocation.longitude != null) {
        setState(() {
          _currentP = LatLng(currentLocation.latitude!, currentLocation.longitude!);

          // Update current location marker
          final MarkerId markerId = MarkerId("_currentLocation");
          final Marker marker = Marker(
            markerId: markerId,
            position: _currentP!,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
            infoWindow: InfoWindow(title: "Current Location"),
          );
          markers[markerId] = marker;

          // If destination is already set, update the polyline
          if (_destinationP != null) {
            updateDirections(_currentP!, _destinationP!);
          }
        });
      }
    });
  }

  Future<void> updateDirections(LatLng start, LatLng end) async {
    // Get travel time and route information
    await getDirectionDetails(start, end);

    // Get polyline coordinates
    List<LatLng> polylineCoordinates = await getPolylinePoints(start, end);

    // Update polyline on map
    generatePolylineFromPoints(polylineCoordinates);

    // Add destination marker
    final MarkerId markerId = MarkerId("_searchDestination");
    final Marker marker = Marker(
      markerId: markerId,
      position: end,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      infoWindow: InfoWindow(
        title: "Destination",
        snippet: "$travelTime • Est. Cost: $transportationCost",
      ),
    );

    setState(() {
      markers[markerId] = marker;
    });
  }

  Future<void> getDirectionDetails(LatLng start, LatLng end) async {
    final String url =
        'https://maps.googleapis.com/maps/api/directions/json?'
        'origin=${start.latitude},${start.longitude}'
        '&destination=${end.latitude},${end.longitude}'
        '&mode=driving'
        '&key=$GOOGLE_MAPS_API_KEY';

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['status'] == 'OK') {
          // Extract distance value for calculation
          int distanceValue = data['routes'][0]['legs'][0]['distance']['value']; // in meters

          // Convert to kilometers
          distanceInKm = distanceValue / 1000;

          // Calculate transportation cost
          String cost = calculateTransportationCost(distanceInKm!, selectedMode);

          setState(() {
            // Extract travel time and distance text from the response
            travelTime = data['routes'][0]['legs'][0]['duration']['text'];
            travelDistance = data['routes'][0]['legs'][0]['distance']['text'];
            transportationCost = cost;
          });
        } else {
          debugPrint('Direction API error: ${data['status']}');
        }
      } else {
        debugPrint('Failed to fetch directions: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error getting directions: $e');
    }
  }

  String calculateTransportationCost(double distance, String mode) {
    double cost;

    // Cost calculation: BASE_FARE + (distance * COST_PER_KM)
    if (mode == 'car') {
      cost = CAR_BASE_FARE + (distance * CAR_COST_PER_KM);
    } else {
      cost = THREEWHEEL_BASE_FARE + (distance * THREEWHEEL_COST_PER_KM);
    }

    // Round to nearest 10
    cost = (cost / 10).round() * 10;

    return "LKR ${cost.toStringAsFixed(0)}";
  }

  Future<List<LatLng>> getPolylinePoints(LatLng start, LatLng end) async {
    List<LatLng> polylineCoordinates = [];
    PolylinePoints polylinePoints = PolylinePoints();

    PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
      GOOGLE_MAPS_API_KEY,
      PointLatLng(start.latitude, start.longitude),
      PointLatLng(end.latitude, end.longitude),
      travelMode: TravelMode.driving,
    );

    if (result.points.isNotEmpty) {
      for (var point in result.points) {
        polylineCoordinates.add(LatLng(point.latitude, point.longitude));
      }
    } else {
      debugPrint("Error retrieving polyline: ${result.errorMessage}");
    }

    return polylineCoordinates;
  }

  void generatePolylineFromPoints(List<LatLng> polylineCoordinates) {
    // Clear previous polylines
    polylines.clear();

    PolylineId id = const PolylineId("route");
    Polyline polyline = Polyline(
      polylineId: id,
      color: Colors.black,
      points: polylineCoordinates,
      width: 5,
    );

    setState(() {
      polylines[id] = polyline;
    });
  }
}