import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:google_place/google_place.dart';
import 'package:location/location.dart' as loc;
import 'package:http/http.dart' as http;
import 'dart:convert';

const String GOOGLE_MAPS_API_KEY = "AIzaSyDPPGBYGwYTOrWtL9dNmiXkjhrsGS6sFTY"; // Don't forget to replace

// Constants for transportation cost calculation
const double CAR_BASE_FARE = 50.0; // Base fare for car in local currency (e.g., LKR)
const double CAR_COST_PER_KM = 40.0; // Cost per kilometer for car

const double THREEWHEEL_BASE_FARE = 60.0; // Base fare for threewheel in local currency
const double THREEWHEEL_COST_PER_KM = 50.0; // Cost per kilometer for threewheel

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final loc.Location _locationController = loc.Location();
  final Completer<GoogleMapController> _mapController = Completer<GoogleMapController>();
  final TextEditingController _searchController = TextEditingController();

  static const LatLng _pGooglePlex = LatLng(6.927079, 79.861244);
  static const LatLng _pApplePark = LatLng(6.933850, 79.844860);
  LatLng? _currentP;
  LatLng? _destinationP;

  Map<PolylineId, Polyline> polylines = {};
  Map<MarkerId, Marker> markers = {};
  late GooglePlace googlePlace;
  List<AutocompletePrediction> predictions = [];

  String? travelTime;
  String? travelDistance;
  String? transportationCost;

  // Transportation mode
  String selectedMode = 'car'; // Default mode

  // Raw values for calculation
  double? distanceInKm;

  @override
  void initState() {
    super.initState();
    googlePlace = GooglePlace('AIzaSyBbLd67HZT9EYb8Xi7ySuVWJVBmLRFREjM');
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

          // Search Bar
          Positioned(
            top: 40,
            left: 15,
            right: 15,
            child: Column(
              children: [
                Material(
                  elevation: 5,
                  borderRadius: BorderRadius.circular(10),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: "Search location",
                      prefixIcon: const Icon(Icons.search),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
                    ),
                    onChanged: (value) {
                      if (value.isNotEmpty) {
                        autoCompleteSearch(value);
                      } else {
                        setState(() {
                          predictions = [];
                        });
                      }
                    },
                  ),
                ),

                // Prediction list
                if (predictions.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 5),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: predictions.length,
                      itemBuilder: (context, index) {
                        return ListTile(
                          leading: const Icon(Icons.location_on),
                          title: Text(predictions[index].description ?? ""),
                          onTap: () async {
                            final placeId = predictions[index].placeId!;
                            final details = await googlePlace.details.get(placeId);
                            if (details != null && details.result != null && details.result!.geometry != null) {
                              final location = details.result!.geometry!.location!;
                              LatLng newPos = LatLng(location.lat!, location.lng!);

                              setState(() {
                                _destinationP = newPos;
                                predictions = [];
                                _searchController.clear();
                              });

                              _cameraToPosition(newPos);

                              // Draw route to the selected destination
                              if (_currentP != null) {
                                updateDirections(_currentP!, _destinationP!);
                              }
                            }
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

          // Transportation mode selection
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

          // Travel Info Panel (Time, Distance, Cost)
          if (travelTime != null && travelDistance != null)
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      spreadRadius: 1,
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.access_time, color: Colors.blue),
                            const SizedBox(width: 8),
                            Text(
                              travelTime!,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            const Icon(Icons.straighten, color: Colors.blue),
                            const SizedBox(width: 8),
                            Text(
                              travelDistance!,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (transportationCost != null)
                      Container(
                        margin: const EdgeInsets.only(top: 12),
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              selectedMode == 'car' ? Icons.directions_car : Icons.local_taxi,
                              color: Colors.blue,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "Estimated Cost: $transportationCost",
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                          ],
                        ),
                      )
                  ],
                ),
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

          // Add fixed markers
          markers[MarkerId("_sourceLocation")] = Marker(
            markerId: MarkerId("_sourceLocation"),
            position: _pGooglePlex,
          );

          markers[MarkerId("_destinationLocation")] = Marker(
            markerId: MarkerId("_destinationLocation"),
            position: _pApplePark,
          );

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
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
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

    // Simplified calculation: BASE_FARE + (distance * COST_PER_KM)
    if (mode == 'car') {
      cost = CAR_BASE_FARE + (distance * CAR_COST_PER_KM);
    } else { // threewheel
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
      color: Colors.blue,
      points: polylineCoordinates,
      width: 5,
    );

    setState(() {
      polylines[id] = polyline;
    });
  }

  void autoCompleteSearch(String value) async {
    var result = await googlePlace.autocomplete.get(value);
    if (result != null && result.predictions != null && mounted) {
      setState(() {
        predictions = result.predictions!;
      });
    }
  }
}