const mem = new WebAssembly.Memory({ initial: 2000, maximum: 65536, shared: false });
const memInterface = new odin.WasmMemoryInterface();
memInterface.setMemory(mem);
const wgpuInterface = new odin.WebGPUInterface(memInterface);

Ammo().then(function(Ammo) {
    odin.runWasm("wasm-src.wasm", null, { wgpu: wgpuInterface.getInterface()}, memInterface, /*intSize=8*/);

    // let collisionConfiguration  = new Ammo.btDefaultCollisionConfiguration(),
    //     dispatcher              = new Ammo.btCollisionDispatcher(collisionConfiguration),
    //     overlappingPairCache    = new Ammo.btDbvtBroadphase(),
    //     solver                  = new Ammo.btSequentialImpulseConstraintSolver();
    // physicsWorld           = new Ammo.btDiscreteDynamicsWorld(dispatcher, overlappingPairCache, solver, collisionConfiguration);
    // physicsWorld.setGravity(new Ammo.btVector3(0, -10, 0));


    // let transform = new Ammo.btTransform();
    // transform.setIdentity();
    // transform.setOrigin( new Ammo.btVector3( 0,0,0 ) );
    // transform.setRotation( new Ammo.btQuaternion( 0,0,0,1 ) );
    // let motionState = new Ammo.btDefaultMotionState( transform );

    // let colShape = new Ammo.btBoxShape( new Ammo.btVector3( 1,1,1) );
    // colShape.setMargin( 0.05 );

    // let localInertia = new Ammo.btVector3( 0, 0, 0 );
    // colShape.calculateLocalInertia(1, localInertia );

    // let rbInfo = new Ammo.btRigidBodyConstructionInfo( 1, motionState, colShape, localInertia );
    // let body = new Ammo.btRigidBody( rbInfo );


    // physicsWorld.addRigidBody( body );

    // rigidBodies = [];
    // tmpTrans = new Ammo.btTransform();
    // rigidBodies.push(body);

    // // Step world
    // for ( let deltaTime = 0; deltaTime < 24; deltaTime+= 0.2 ) {

    //     physicsWorld.stepSimulation( deltaTime, 10 );

    //     // Update rigid bodies
    //     for (let i = 0; i < rigidBodies.length; i++ ) {
    //         let objThree = rigidBodies[ i ];
    //         let objAmmo = objThree;
    //         let ms = objAmmo.getMotionState();
    //         if ( ms ) {
    //             ms.getWorldTransform( tmpTrans );
    //             let p = tmpTrans.getOrigin();
    //             let q = tmpTrans.getRotation();
    //             console.log(p.x(), p.y(), p.z());
    //             console.log(q.x(), q.y(), q.z(), q.w());
    //         }
    //     }
    // }
});